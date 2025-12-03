package luceedebug.coreinject.frame;

import lucee.runtime.PageContext;
import lucee.runtime.PageContextImpl;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicLong;

import luceedebug.*;
import luceedebug.coreinject.CfValueDebuggerBridge;
import luceedebug.coreinject.DebugEntity;
import luceedebug.coreinject.ValTracker;
import luceedebug.coreinject.CfValueDebuggerBridge.MarkerTrait;

/**
 * Adapter that wraps Lucee7's native DebuggerFrame to implement IDebugFrame.
 * Uses reflection to access the new Lucee7 APIs so we can compile against older Lucee versions.
 *
 * This is used when Lucee's DEBUGGER_ENABLED=true and provides the CFML frame stack
 * without requiring bytecode instrumentation.
 */
public class NativeDebugFrame implements IDebugFrame {
	static private AtomicLong nextId = new AtomicLong( 0 );

	// Reflection cache - initialized once
	private static volatile Boolean nativeFrameSupportAvailable = null;
	private static Field debuggerEnabledField = null;
	private static Method getDebuggerFramesMethod = null;
	private static Method getLineMethod = null;
	private static Method setLineMethod = null;
	private static Field localField = null;
	private static Field argumentsField = null;
	private static Field variablesField = null;
	private static Field pageSourceField = null;
	private static Field functionNameField = null;
	private static Method getDisplayPathMethod = null;

	private final Object nativeFrame; // PageContextImpl.DebuggerFrame
	private final PageContext pageContext;
	private final ValTracker valTracker;
	private final String sourceFilePath;
	private final String functionName;
	private final long id;
	private final int depth;

	// Scope references from the native frame
	private final Object local;      // lucee.runtime.type.scope.Local
	private final Object arguments;  // lucee.runtime.type.scope.Argument
	private final Object variables;  // lucee.runtime.type.scope.Variables

	// lazy initialized on request for scopes
	private LinkedHashMap<String, CfValueDebuggerBridge> scopes_ = null;

	private NativeDebugFrame( Object nativeFrame, PageContext pageContext, ValTracker valTracker, int depth ) throws Exception {
		this.nativeFrame = nativeFrame;
		this.pageContext = pageContext;
		this.valTracker = valTracker;
		this.id = nextId.incrementAndGet();
		this.depth = depth;

		// Extract fields using reflection
		this.local = localField.get( nativeFrame );
		this.arguments = argumentsField.get( nativeFrame );
		this.variables = variablesField.get( nativeFrame );
		Object pageSource = pageSourceField.get( nativeFrame );
		this.sourceFilePath = (String) getDisplayPathMethod.invoke( pageSource );
		this.functionName = (String) functionNameField.get( nativeFrame );
	}

	@Override
	public String getSourceFilePath() {
		return sourceFilePath;
	}

	@Override
	public long getId() {
		return id;
	}

	@Override
	public String getName() {
		return functionName != null ? functionName : "??";
	}

	@Override
	public int getDepth() {
		return depth;
	}

	@Override
	public int getLine() {
		try {
			return (int) getLineMethod.invoke( nativeFrame );
		} catch ( Exception e ) {
			return 0;
		}
	}

	@Override
	public void setLine( int line ) {
		try {
			setLineMethod.invoke( nativeFrame, line );
		} catch ( Exception e ) {
			// ignore
		}
	}

	private void checkedPutScopeRef( String name, Object scope ) {
		if ( scope != null && scope instanceof Map ) {
			var v = new MarkerTrait.Scope( (Map<?, ?>) scope );
			CfValueDebuggerBridge.pin( v );
			scopes_.put( name, new CfValueDebuggerBridge( valTracker, v ) );
		}
	}

	private void lazyInitScopeRefs() {
		if ( scopes_ != null ) {
			return;
		}

		scopes_ = new LinkedHashMap<>();

		// Frame-specific scopes from native DebuggerFrame
		checkedPutScopeRef( "local", local );
		checkedPutScopeRef( "arguments", arguments );
		checkedPutScopeRef( "variables", variables );

		// Global scopes from PageContext - these are shared across frames
		try {
			checkedPutScopeRef( "application", pageContext.applicationScope() );
		} catch ( Throwable e ) { /* scope not available */ }

		try {
			checkedPutScopeRef( "form", pageContext.formScope() );
		} catch ( Throwable e ) { /* scope not available */ }

		try {
			checkedPutScopeRef( "request", pageContext.requestScope() );
		} catch ( Throwable e ) { /* scope not available */ }

		try {
			if ( pageContext.getApplicationContext().isSetSessionManagement() ) {
				checkedPutScopeRef( "session", pageContext.sessionScope() );
			}
		} catch ( Throwable e ) { /* scope not available */ }

		try {
			checkedPutScopeRef( "server", pageContext.serverScope() );
		} catch ( Throwable e ) { /* scope not available */ }

		try {
			checkedPutScopeRef( "url", pageContext.urlScope() );
		} catch ( Throwable e ) { /* scope not available */ }

		// Try to get 'this' scope from variables if it's a ComponentScope
		try {
			if ( variables != null && variables.getClass().getName().equals( "lucee.runtime.ComponentScope" ) ) {
				Method getComponentMethod = variables.getClass().getMethod( "getComponent" );
				Object component = getComponentMethod.invoke( variables );
				checkedPutScopeRef( "this", component );
			}
		} catch ( Throwable e ) { /* scope not available */ }
	}

	@Override
	public IDebugEntity[] getScopes() {
		lazyInitScopeRefs();
		IDebugEntity[] result = new DebugEntity[scopes_.size()];
		int i = 0;
		for ( var kv : scopes_.entrySet() ) {
			String name = kv.getKey();
			CfValueDebuggerBridge entityRef = kv.getValue();
			var entity = new DebugEntity();
			entity.name = name;
			entity.namedVariables = entityRef.getNamedVariablesCount();
			entity.indexedVariables = entityRef.getIndexedVariablesCount();
			entity.expensive = true;
			entity.variablesReference = entityRef.id;
			result[i] = entity;
			i += 1;
		}
		return result;
	}

	/**
	 * Initialize reflection handles for Lucee7's native debugger frame support.
	 * Returns true if initialization succeeded (Lucee7 with DEBUGGER_ENABLED=true).
	 */
	private static synchronized boolean initReflection() {
		if ( nativeFrameSupportAvailable != null ) {
			return nativeFrameSupportAvailable;
		}

		try {
			Class<?> pciClass = PageContextImpl.class;

			// Check if DEBUGGER_ENABLED field exists and is true
			debuggerEnabledField = pciClass.getField( "DEBUGGER_ENABLED" );
			boolean enabled = debuggerEnabledField.getBoolean( null );
			if ( !enabled ) {
				nativeFrameSupportAvailable = false;
				return false;
			}

			// Get the getDebuggerFrames method
			getDebuggerFramesMethod = pciClass.getMethod( "getDebuggerFrames" );

			// Get DebuggerFrame class (inner class of PageContextImpl)
			Class<?> debuggerFrameClass = Class.forName( "lucee.runtime.PageContextImpl$DebuggerFrame" );

			// Get DebuggerFrame fields and methods
			localField = debuggerFrameClass.getField( "local" );
			argumentsField = debuggerFrameClass.getField( "arguments" );
			variablesField = debuggerFrameClass.getField( "variables" );
			pageSourceField = debuggerFrameClass.getField( "pageSource" );
			functionNameField = debuggerFrameClass.getField( "functionName" );
			getLineMethod = debuggerFrameClass.getMethod( "getLine" );
			setLineMethod = debuggerFrameClass.getMethod( "setLine", int.class );

			// Get PageSource.getDisplayPath method
			Class<?> pageSourceClass = Class.forName( "lucee.runtime.PageSource" );
			getDisplayPathMethod = pageSourceClass.getMethod( "getDisplayPath" );

			nativeFrameSupportAvailable = true;
			System.out.println( "[luceedebug] Native Lucee7 debugger frame support detected and enabled" );
			return true;

		} catch ( Throwable e ) {
			// Lucee version doesn't have native debugger frame support
			nativeFrameSupportAvailable = false;
			return false;
		}
	}

	/**
	 * Check if native debugger frames are available in this Lucee version.
	 * Returns true if DEBUGGER_ENABLED is true in Lucee7+.
	 */
	public static boolean isNativeFrameSupportAvailable() {
		return initReflection();
	}

	/**
	 * Get frames from Lucee's native debugger frame stack.
	 * Returns null if native frames are not available or empty.
	 */
	public static IDebugFrame[] getNativeFrames( PageContext pageContext, ValTracker valTracker ) {
		if ( !isNativeFrameSupportAvailable() ) {
			return null;
		}

		try {
			PageContextImpl pci = (PageContextImpl) pageContext;
			Object[] nativeFrames = (Object[]) getDebuggerFramesMethod.invoke( pci );

			if ( nativeFrames == null || nativeFrames.length == 0 ) {
				return null;
			}

			// Convert to IDebugFrame array, filtering frames with line 0
			ArrayList<IDebugFrame> result = new ArrayList<>();

			// Native frames are in push order (oldest first), DAP expects newest first
			for ( int i = nativeFrames.length - 1; i >= 0; i-- ) {
				Object nf = nativeFrames[i];
				int line = (int) getLineMethod.invoke( nf );

				// Skip frames with line 0 (not yet stepped into)
				if ( line == 0 ) {
					continue;
				}

				result.add( new NativeDebugFrame( nf, pageContext, valTracker, i ) );
			}

			if ( result.isEmpty() ) {
				return null;
			}

			return result.toArray( new IDebugFrame[0] );

		} catch ( Throwable e ) {
			System.err.println( "[luceedebug] Error getting native frames: " + e.getMessage() );
			return null;
		}
	}
}
