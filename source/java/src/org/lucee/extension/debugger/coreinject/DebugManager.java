package org.lucee.extension.debugger.coreinject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.lang.ref.Cleaner;
import java.lang.ref.WeakReference;
import java.lang.reflect.Array;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.TimeUnit;
import java.util.function.Supplier;

import com.sun.jdi.Bootstrap;
import com.sun.jdi.VirtualMachine;
import com.sun.jdi.VirtualMachineManager;
import com.sun.jdi.connect.AttachingConnector;

import static lucee.loader.engine.CFMLEngine.DIALECT_CFML;
import lucee.loader.engine.CFMLEngine;
import lucee.loader.engine.CFMLEngineFactory;
import lucee.runtime.PageContext;
import lucee.runtime.engine.ThreadLocalPageContext;
import lucee.runtime.exp.PageException;
import lucee.runtime.functions.conversion.SerializeJSON;
import lucee.runtime.functions.dynamicEvaluation.Evaluate;
import lucee.runtime.functions.system.CFFunction;
import lucee.runtime.op.Caster;
import lucee.runtime.type.FunctionValueImpl;
import lucee.runtime.type.util.KeyConstants;
import lucee.runtime.util.ClassUtil;
import lucee.runtime.util.PageContextUtil;
import org.lucee.extension.debugger.Config;
import org.lucee.extension.debugger.DapServer;
import org.lucee.extension.debugger.Either;
import org.lucee.extension.debugger.GlobalIDebugManagerHolder;
import org.lucee.extension.debugger.ICfValueDebuggerBridge;
import org.lucee.extension.debugger.IDebugEntity;
import org.lucee.extension.debugger.IDebugFrame;
import org.lucee.extension.debugger.IDebugManager;
import org.lucee.extension.debugger.coreinject.frame.DebugFrame;
import org.lucee.extension.debugger.coreinject.frame.Frame;
import org.lucee.extension.debugger.coreinject.frame.Frame.FrameContext;

public class DebugManager implements IDebugManager {

    /**
     * see DebugManager.dot for class loader graph
     */
    public DebugManager() {
        // Sanity check that we're being loaded as expected.
        // DebugManager must be loaded with the "lucee core loader", which means we need to have already seen PageContextImpl.
        // Using the "core loader" (which is used to load, amongst other things, PageContextImpl) gives us
        // same-classloader-visibility (term for that?) to PageContextImpl, so we can ask it for detailed runtime info.
        if (GlobalIDebugManagerHolder.luceeCoreLoader == null) {
            System.out.println("[luceedebug] error - expected org.lucee.extension.debugger.coreinject.DebugManager to be loaded with the Lucee core loader, but the Lucee core loader hasn't been loaded yet.");
            throw new IllegalStateException("[luceedebug] DebugManager must be loaded with the Lucee core loader, but the Lucee core loader hasn't been seen yet.");
        }
        else if (GlobalIDebugManagerHolder.luceeCoreLoader != this.getClass().getClassLoader()) {
            System.out.println("[luceedebug] error - expected org.lucee.extension.debugger.coreinject.DebugManager to be loaded with the Lucee core loader, but it is being loaded with classloader='" + this.getClass().getClassLoader() + "'.");
            System.out.println("[luceedebug]         lucee coreLoader has been seen, and is " + GlobalIDebugManagerHolder.luceeCoreLoader);
            throw new IllegalStateException("[luceedebug] DebugManager loaded with wrong classloader: " + this.getClass().getClassLoader() + " (expected: " + GlobalIDebugManagerHolder.luceeCoreLoader + ")");
        }
        else {
            // ok, no problem; nothing to do.
            // This should be a singleton, but the instance is stored outside of coreinject.
        }
    }

    // definitely non-null after spawnWorker
    private Config config_ = null;

    public void spawnWorker(Config config, String jdwpHost, int jdwpPort, String debugHost, int debugPort) {
        config_ = config;
        final String threadName = "luceedebug-worker";

        System.out.println("[luceedebug] attempting jdwp self connect to jdwp on " + jdwpHost + ":" + jdwpPort + "...");

        VirtualMachine vm = jdwpSelfConnect(jdwpHost, jdwpPort);
        LuceeVm luceeVm = new LuceeVm(config, vm);

        var dapThread = new Thread(() -> {
            System.out.println("[luceedebug] jdwp self connect OK");
            try {
                DapServer.createForSocket(luceeVm, config, debugHost, debugPort);
            } catch (Throwable t) {
                System.out.println("[luceedebug] DAP server thread failed: " + t.getMessage());
                t.printStackTrace();
            }
        }, threadName);
        // Daemon so LUCEE_ENABLE_WARMUP can exit the JVM cleanly after Lucee's bundle
        // compile - a non-daemon thread parked on ServerSocket.accept() would block exit.
        // During a real debug session Tomcat's own non-daemon threads keep the JVM alive.
        dapThread.setDaemon(true);
        dapThread.start();
    }

    static private AttachingConnector getConnector() {
        VirtualMachineManager vmm;
        try {
            vmm = Bootstrap.virtualMachineManager();
        }
        catch (NoClassDefFoundError e) {
            if (e.getMessage().contains("com/sun/jdi/Bootstrap")) {
                // this is a common error
                System.out.println("[luceedebug]");
                System.out.println("[luceedebug]");
                System.out.println("[luceedebug] couldn't load a com.sun.jdi.VirtualMachineManager; you might not be running the JDK version of your Java release");
                System.out.println("[luceedebug]");
                System.out.println("[luceedebug]");
            }
            throw e;
        }

        var attachingConnectors = vmm.attachingConnectors();
        for (var c : attachingConnectors) {
            if (c.name().equals("com.sun.jdi.SocketAttach")) {
                return c;
            }
        }
        System.out.println("[luceedebug] no socket attaching connector found - agent mode cannot debug.");
        throw new IllegalStateException("[luceedebug] no SocketAttach JDI connector found - JDK required for agent mode debugging.");
    }

    static private VirtualMachine jdwpSelfConnect(String host, int port) {
        var connector = getConnector();
        var args = connector.defaultArguments();
        args.get("hostname").setValue(host);
        args.get("port").setValue(Integer.toString(port));
        try {
            return connector.attach(args);
        }
        catch (Throwable e) {
            e.printStackTrace();
            throw new RuntimeException("[luceedebug] JDWP self-connect failed (host=" + host + ", port=" + port + ")", e);
        }
    }

    private String wrapDumpInHtmlDoc(String s) {
        return "<!DOCTYPE html><html><body>" + s + "</body></html>";
    }

    // We need a PageContext to create a fresh ephemeral one with its own output buffer.
    // The caller only has a variablesReference, so we iterate suspendedThreads and pick
    // the first one that has an associated PageContext.
    synchronized public String doDump(ArrayList<Thread> suspendedThreads, int variableID) {
        final var pageContext = maybeNull_findPageContext(suspendedThreads);
        if (pageContext == null) {
            var msgBuilder = new StringBuilder();
            suspendedThreads.forEach(thread -> msgBuilder.append("<div>" + thread + "</div>"));
            return "<div>couldn't get a page context, iterated over threads:</div>" + msgBuilder.toString();
        }

        final var entity = findEntity(variableID);
        if (entity.isRight()) {
            return "<div>" + entity.right + "</div>";
        }

        return doDump(pageContext, entity.left);
    }

    synchronized public String doDumpAsJSON(ArrayList<Thread> suspendedThreads, int variableID) {
        final var pageContext = maybeNull_findPageContext(suspendedThreads);
        if (pageContext == null) {
            return "\"couldn't find a page context to do work on\"";
        }

        final var entity = findEntity(variableID);
        if (entity.isRight()) {
            return "\"" + entity.right.replace("\"", "\\\"") + "\"";
        }

        return doDumpAsJSON(pageContext, entity.left);
    }

    synchronized private Either<Object, String> findEntity(int variableID) {
        return Either
            .fromOpt(valTracker.maybeGetFromId(variableID))
            .bimap(
                taggedObj -> taggedObj.obj,
                v -> "Lookup of ref having ID " + variableID + " found nothing."
            );
    }
    
    /**
     * synchronized might be unnecessary here
     */
    synchronized private PageContext maybeNull_findPageContext(ArrayList<Thread> suspendedThreads) {
        final var pageContextRef = ((Supplier<WeakReference<PageContext>>) () -> {
            for (var thread : suspendedThreads) {
                var pageContextRef_ = pageContextByThread.get(thread);
                if (pageContextRef_ != null) {
                    return pageContextRef_;
                }
            }
            return null;
        }).get();
        return pageContextRef == null ? null : pageContextRef.get();
    }

    public static class PageContextAndOutputStream {
        public final PageContext pageContext;
        public final ByteArrayOutputStream outStream;
        public PageContextAndOutputStream(PageContext pageContext, ByteArrayOutputStream outStream) {
            this.pageContext = pageContext;
            this.outStream = outStream;
        }

        // Create a fresh PageContext piggy-backing off another one's ConfigWeb.
        //
        // Uses ThreadUtil.createPageContext via the loader's ClassUtil. This avoids
        // calling pc.getServletConfig() entirely - that method's return type flipped
        // from javax to jakarta between Lucee 6 and 7, and since this agent jar is
        // compiled against jakarta, a direct call throws NoSuchMethodError on 6.x.
        // ConfigWeb is servlet-API-agnostic so one agent jar works on both runtimes.
        public static PageContextAndOutputStream ephemeralPageContextFromOther(PageContext pc) throws Exception {
            final var outputStream = new ByteArrayOutputStream();

            CFMLEngine engine = CFMLEngineFactory.getInstance();
            ClassUtil classUtil = engine.getClassUtil();

            Class<?> threadUtilClass = classUtil.loadClass("lucee.runtime.thread.ThreadUtil");
            Object emptyCookies = getEmptyCookieArray(classUtil);

            PageContext freshEphemeralPageContext = (PageContext) classUtil.callStaticMethod(
                threadUtilClass,
                "createPageContext",
                new Object[] {
                    pc.getConfig(),    // ConfigWeb
                    outputStream,      // OutputStream
                    "",                // serverName
                    "",                // requestURI
                    "",                // queryString
                    emptyCookies,      // Cookie[] (jakarta or javax per runtime)
                    null,              // Pair[] headers
                    null,              // byte[] body
                    null,              // Pair[] parameters
                    null,              // Struct attributes
                    false,             // register (caller handles ThreadLocalPageContext.register)
                    99999L             // timeout
                }
            );

            return new PageContextAndOutputStream(freshEphemeralPageContext, outputStream);
        }

        private static Object getEmptyCookieArray(ClassUtil classUtil) throws Exception {
            try {
                // jakarta first (Lucee 7+)
                Class<?> cookieClass = classUtil.loadClass("jakarta.servlet.http.Cookie");
                return Array.newInstance(cookieClass, 0);
            }
            catch (Exception e) {
                // javax fallback (Lucee 5/6)
                Class<?> cookieClass = classUtil.loadClass("javax.servlet.http.Cookie");
                return Array.newInstance(cookieClass, 0);
            }
        }
    }

    // this is "single threaded" for now, only a single dumpable thing is tracked at once,
    // pushing another dump overwrites the old dump.
    synchronized private String doDump(PageContext pageContext, Object someDumpable) {
        // Scope references from DAP arrive wrapped in MarkerTrait.Scope; unwrap so writeDump
        // iterates the scope contents, not the wrapper's Java reflection metadata.
        // (Native mode does the same in NativeLuceeVm.doDumpNative.)
        final Object dumpable = (someDumpable instanceof CfValueDebuggerBridge.MarkerTrait.Scope)
            ? ((CfValueDebuggerBridge.MarkerTrait.Scope) someDumpable).scopelike
            : someDumpable;
        final var result = new Object(){ String value = "if this text is present, something went wrong when calling writeDump(...)"; };
        final var thread = new Thread(() -> {
            try {
                final var ephemeralContext = PageContextAndOutputStream.ephemeralPageContextFromOther(pageContext);
                final var freshEphemeralPageContext = ephemeralContext.pageContext;
                final var outputStream = ephemeralContext.outStream;

                ThreadLocalPageContext.register(freshEphemeralPageContext);

                CFFunction.call(
                    freshEphemeralPageContext, new Object[]{
                        FunctionValueImpl.newInstance(KeyConstants.___filename, "writeDump.cfm"),
                        FunctionValueImpl.newInstance(KeyConstants.___name, "writeDump"),
                        FunctionValueImpl.newInstance(KeyConstants.___isweb, Boolean.FALSE),
                        FunctionValueImpl.newInstance(KeyConstants.___mapping, "/mapping-function"),
                        dumpable
                    });

                freshEphemeralPageContext.flush();
                result.value = wrapDumpInHtmlDoc(new String(outputStream.toByteArray(), "UTF-8"));

                PageContextUtil.releasePageContext(
                    /*PageContext pc*/ freshEphemeralPageContext,
                    /*boolean register*/ true
                );

                outputStream.close();

                ThreadLocalPageContext.release();
            }
            catch (Throwable e) {
                // Log only - never kill the host JVM. The preset result.value fallback stands.
                e.printStackTrace();
            }
        });

        thread.start();

        try {
            // needs to be on its own thread for PageContext reasons
            // but we still want to do this synchronously
            thread.join();
        }
        catch (Throwable e) {
            e.printStackTrace();
        }

        return result.value;
    }

    synchronized private String doDumpAsJSON(PageContext pageContext, Object someDumpable) {
        // Unwrap scope wrapper (same reason as doDump).
        final Object dumpable = (someDumpable instanceof CfValueDebuggerBridge.MarkerTrait.Scope)
            ? ((CfValueDebuggerBridge.MarkerTrait.Scope) someDumpable).scopelike
            : someDumpable;
        final var result = new Object(){ String value = "\"Something went wrong when calling serializeJSON(...)\""; };
        final var thread = new Thread(() -> {
            try {
                final var ephemeralContext = PageContextAndOutputStream.ephemeralPageContextFromOther(pageContext);
                final var freshEphemeralPageContext = ephemeralContext.pageContext;
                final var outputStream = ephemeralContext.outStream;

                ThreadLocalPageContext.register(freshEphemeralPageContext);

                result.value = (String)SerializeJSON.call(
                    /*PageContext pc*/ freshEphemeralPageContext,
                    /*Object var*/ dumpable,
                    /*Object queryFormat*/"struct"
                );

                PageContextUtil.releasePageContext(
                    /*PageContext pc*/ freshEphemeralPageContext,
                    /*boolean register*/ true
                );

                outputStream.close();

                ThreadLocalPageContext.release();
            }
            catch (Throwable e) {
                // Log only - never kill the host JVM. The preset result.value fallback stands.
                e.printStackTrace();
            }
        });

        thread.start();

        try {
            // needs to be on its own thread for PageContext reasons
            // but we still want to do this synchronously
            thread.join();
        }
        catch (Throwable e) {
            e.printStackTrace();
        }

        return result.value;
    }

    public Either</*err*/String, /*ok*/Either<ICfValueDebuggerBridge, String>> evaluate(Long frameID, String expr) {
        final var zzzframe = frameByFrameID.get(frameID);
        if (!(zzzframe instanceof Frame)) {
            return Either.Left("<<no such frame>>");
        }

        Frame frame = (Frame)zzzframe;

        return doEvaluate(frame, expr)
            .bimap(
                err -> err,
                ok -> {
                    // what about bool, Long, etc. ?...
                    if (ok == null) {
                        return Either.Right("null");
                    }
                    else if (ok instanceof String) {
                        return Either.Right("\"" + ((String)ok).replaceAll("\"", "\\\"") + "\"");
                    }
                    else if (ok instanceof Number || ok instanceof Boolean) {
                        return Either.Right(ok.toString());
                    }
                    else {
                        return Either.Left(frame.trackEvalResult(ok));
                    }
                }
            );
    }

    // concurrency here needs to be at the level of the DAP server?
    // does the DAP server do multiple concurrent requests ... ? ... it's all one socket so probably not ? ... well many inbound messages can be being serviced ...
    private Either</*err*/String, /*ok*/Object> doEvaluate(Frame frame, String expr) {
        try {
            return CompletableFuture
                .supplyAsync(
                    (Supplier<Either<String,Object>>)(() -> {
                        return frame
                            .getFrameContext()
                            .doWorkInThisFrame((Supplier<Either<String,Object>>)() -> {
                                try {
                                    ThreadLocalPageContext.register(frame.getFrameContext().pageContext);
                                    return ExprEvaluator.eval(frame, expr);
                                }
                                catch (Throwable e) {
                                    return Either.Left(e.getMessage());
                                }
                                finally {
                                    ThreadLocalPageContext.release();
                                }
                            });
                    })
                ).get(5, TimeUnit.SECONDS);
        }
        catch (Throwable e) {
            return Either.Left(e.getMessage());
        }
    }

    public boolean evaluateAsBooleanForConditionalBreakpoint(Thread thread, String expr) {
        var stack = cfStackByThread.get(thread);
        if (stack == null) {
            return false;
        }
        
        // We have observed concurrent read/writes here to the stack frame list, where the expected frame is popped off the stack
        // somewhere between determining the index of the last element and attempting to access the last element.
        // It is not expected to happen often, so just catch/log/return false in this case.
        try {
            if (stack.isEmpty()) {
                return false;
            }

            DebugFrame frame = stack.get(stack.size() - 1); // n.b. stack can be empty despite our prior check

            if (frame instanceof Frame) {
                return doEvaluateAsBoolean((Frame)frame, expr);
            }
            else {
                return false;
            }
        }
        catch (IndexOutOfBoundsException e) {
            System.out.println("[luceedebug]: evaluateAsBooleanForConditionalBreakpoint oob stack read, returning `false`");
            return false;
        }
    }

    private boolean doEvaluateAsBoolean(Frame frame, String expr) {
        try {
            return CompletableFuture
                .supplyAsync(
                    (Supplier<Boolean>)(() -> {
                        return frame
                            .getFrameContext()
                            .doWorkInThisFrame((Supplier<Boolean>)() -> {
                                try {
                                    ThreadLocalPageContext.register(frame.getFrameContext().pageContext);
                                    Object obj = Evaluate.call(
                                        frame.getFrameContext().pageContext,
                                        new String[]{expr}
                                    );
                                    return Caster.toBoolean(obj);
                                }
                                catch (PageException e) {
                                    return false;
                                }
                                finally {
                                    ThreadLocalPageContext.release();
                                }
                            });
                    })
                ).get(5, TimeUnit.SECONDS);
        }
        catch (Throwable e) {
            return false;
        }
    }

    private final Cleaner cleaner = Cleaner.create();

    // MapMaker().concurrencyLevel(4).weakKeys().makeMap() ---> ~20% overhead on pushFrame/popFrame
    // ConcurrentHashMap                                   ---> ~10% overhead on pushFrame/popFrame
    // Collections.synchronizedMap(new HashMap<>());       ---> ~12% overhead on pushFrame/popFrame
    private final ConcurrentHashMap<Thread, ArrayList<DebugFrame>> cfStackByThread = new ConcurrentHashMap<>();
    private final ConcurrentHashMap<Thread, WeakReference<PageContext>> pageContextByThread = new ConcurrentHashMap<>();

    private final ConcurrentHashMap<Long, DebugFrame> frameByFrameID = new ConcurrentHashMap<>();
    
    /**
     * an entity represents a Java object that itself is a CF object
     * There is exactly one unique Java object per unique CF object
     * These are nameless values floating in memory, and we wrap them in objects that themselves have IDs
     * Asking for an object (or registering the same object again) should produce the same ID for the same object
     */
    private ValTracker valTracker = new ValTracker(cleaner);

    private CfStepCallback didStepCallback = null;
    public void registerCfStepHandler(CfStepCallback cb) {
        didStepCallback = cb;
    }
    private void notifyStep(Thread thread, int minDistanceToLuceedebugStepNotificationEntryFrame) {
        if (didStepCallback != null) {
            didStepCallback.call(thread, minDistanceToLuceedebugStepNotificationEntryFrame + 1);
        }
    }

    synchronized public IDebugEntity[] getScopesForFrame(long frameID) {
        DebugFrame frame = frameByFrameID.get(frameID);
        //System.out.println("Get scopes for frame, frame was " + frame);
        if (frame == null) {
            return new IDebugEntity[0];
        }
        return frame.getScopes();
    }

    /**
     * @maybeNull_which --> null means "any type"
     */
    synchronized public IDebugEntity[] getVariables(long id, IDebugEntity.DebugEntityType maybeNull_which) {
        return valTracker
            .maybeGetFromId(id)
            .map(taggedObj -> CfValueDebuggerBridge.getAsDebugEntity(valTracker, taggedObj.obj, maybeNull_which))
            .orElseGet(() -> new IDebugEntity[0]);
    }

    synchronized public IDebugFrame[] getCfStack(Thread thread) {
        ArrayList<DebugFrame> stack = cfStackByThread.get(thread);

        // Agent mode: only use bytecode-instrumented frames, no native fallback
        if (stack == null || stack.isEmpty()) {
            return new Frame[0];
        }

        ArrayList<DebugFrame> result = new ArrayList<>();
        result.ensureCapacity(stack.size());

        // go backwards, "most recent first"
        for (int i = stack.size() - 1; i >= 0; --i) {
            DebugFrame frame = stack.get(i);
            if (frame.getLine() == 0) {
                // Frame line not yet set - step notification hasn't run yet
                // This can happen when breakpoint fires before first line executes
                continue;
            }
            else {
                result.add(frame);
            }
        }

        return result.toArray(new Frame[result.size()]);
    }

    static class CfStepRequest {
        // same enum values as jdwp / jvmti
        static final int STEP_INTO = 0;
        static final int STEP_OVER = 1;
        static final int STEP_OUT = 2;

        final long __debug__startTime = System.nanoTime();
        long __debug__stepOverhead = 0;
        int __debug__steps = 0;

        final int startDepth;
        final int type;

        CfStepRequest(int startDepth, int type) {
            this.startDepth = startDepth;
            this.type = type;
        }

        public String toString() {
            var s_type = type == STEP_INTO ? "into" : type == STEP_OVER ? "over" : "out";
            return "(stepRequest // startDepth=" + startDepth + " type=" + s_type + ")";
        }
    };

    public void registerStepRequest(Thread thread, int type) {
        DebugFrame frame = getTopmostFrame(thread);
        if (frame == null) {
            System.err.println("[luceedebug] registerStepRequest: no frames for thread '" + thread + "' (type=" + type + ") - step request ignored");
            return;
        }

        switch (type) {
            case CfStepRequest.STEP_INTO:
                // fallthrough
            case CfStepRequest.STEP_OVER:
                // fallthrough
            case CfStepRequest.STEP_OUT: {
                stepRequestByThread.put(thread, new CfStepRequest(frame.getDepth(), type));
                hasAnyStepRequests = true;
                return;
            }
            default: {
                System.err.println("[luceedebug] registerStepRequest: unknown step type=" + type + " for thread '" + thread + "' - step request ignored");
                return;
            }
        }
    }

    // This holds strongrefs to Thread objects, but requests should be cleared out after their completion
    // It doesn't make sense to have a step request for thread that would otherwise be reclaimable but for our reference to it here
    private ConcurrentHashMap<Thread, CfStepRequest> stepRequestByThread = new ConcurrentHashMap<>();
    // Fast-path flag: volatile read is cheaper than ConcurrentHashMap.isEmpty() or .get()
    private volatile boolean hasAnyStepRequests = false;

    public void clearStepRequest(Thread thread) {
        stepRequestByThread.remove(thread);
        hasAnyStepRequests = !stepRequestByThread.isEmpty();
    }

    public void luceedebug_stepNotificationEntry_step(int lineNumber) {
        Thread currentThread = Thread.currentThread();

        // ALWAYS update the frame's line number, even when not stepping
        // This is required for breakpoints to work - they need to know the current line
        DebugFrame frame = maybeUpdateTopmostFrame(currentThread, lineNumber);

        // Fast path: if not stepping, we're done after updating line number
        if (!hasAnyStepRequests) {
            return;
        }

        final int minDistanceToLuceedebugStepNotificationEntryFrame = 0;

        CfStepRequest request = stepRequestByThread.get(currentThread);
        if (request == null) {
            return;
        }
        else if (frame instanceof Frame) {
            request.__debug__steps++;
            maybeNotifyOfStepCompletion(currentThread, (Frame) frame, request, minDistanceToLuceedebugStepNotificationEntryFrame + 1, System.nanoTime());
        }
        else {
            // no-op
        }
    }

    /**
     * we need to know when stepped out of a udf call, back to the callsite.
     * This is different that "did the frame get popped", because if an exception was thrown, we won't return to the callsite even though the frame does get popped.
     * So we want the debugger to return to the callsite in the normal case, but jump to any catch/finally blocks in the exceptional case.
     */
    public void luceedebug_stepNotificationEntry_stepAfterCompletedUdfCall() {
        // Fast path: single volatile read when not stepping (99.9% of the time)
        if (!hasAnyStepRequests) {
            return;
        }

        final int minDistanceToLuceedebugStepNotificationEntryFrame = 0;

        Thread currentThread = Thread.currentThread();
        DebugFrame frame = getTopmostFrame(currentThread);

        if (frame == null) {
            // just popped last frame?
            return;
        }

        CfStepRequest request = stepRequestByThread.get(currentThread);
        if (request == null) {
            return;
        }
        else if (frame instanceof Frame) {
            request.__debug__steps++;
            maybeNotifyOfStepCompletion(currentThread, (Frame)frame, request, minDistanceToLuceedebugStepNotificationEntryFrame + 1, System.nanoTime());
        }
        else {
            // no-op
        }
    }

    private void maybeNotifyOfStepCompletion(Thread currentThread, Frame frame, CfStepRequest request, int minDistanceToLuceedebugStepNotificationEntryFrame, long start) {
        if (frame.isUdfDefaultValueInitFrame && !config_.getStepIntoUdfDefaultValueInitFrames()) {
            return;
        }

        if (request.type == CfStepRequest.STEP_INTO) {
            // step in, every step is a valid step
            clearStepRequest(currentThread);
            notifyStep(currentThread, minDistanceToLuceedebugStepNotificationEntryFrame + 1);
        }
        else if (request.type == CfStepRequest.STEP_OVER) {
            if (frame.getDepth() > request.startDepth) {
                long end = System.nanoTime();
                request.__debug__stepOverhead += (end - start);
                return;
            }
            else {
                // long end = System.nanoTime();
                // double elapsed_ms = (end - request.__debug__startTime) / 1e6;
                // double stepsPerMs = request.__debug__steps / elapsed_ms;

                // System.out.println("  currentframedepth=" + frame.getDepth() + ", startframedepth=" + request.startDepth + ", notifying native of step occurence...");
                // System.out.println("    " + request.__debug__steps + " cf steps in " + elapsed_ms + "ms for " + stepsPerMs + " steps/ms, overhead was " + (request.__debug__stepOverhead / 1e6) + "ms");

                clearStepRequest(currentThread);
                notifyStep(currentThread, minDistanceToLuceedebugStepNotificationEntryFrame + 1);
            }
        }
        else if (request.type == CfStepRequest.STEP_OUT) {
            if (frame.getDepth() >= request.startDepth) {
                // stepping out, we need to have popped a frame to notify
                return;
            }
            else {
                clearStepRequest(currentThread);
                notifyStep(currentThread, minDistanceToLuceedebugStepNotificationEntryFrame + 1);
            }
        }
        else {
            // unreachable
        }
    }

    private DebugFrame maybeUpdateTopmostFrame(Thread thread, int lineNumber) {
        DebugFrame frame = getTopmostFrame(thread);
        if (frame == null) {
            return null;
        }
        frame.setLine(lineNumber);
        return frame;
    }

    private DebugFrame getTopmostFrame(Thread thread) {
        ArrayList<DebugFrame> stack = cfStackByThread.get(thread);
        if (stack == null || stack.size() == 0) {
            return null;
        }
        return stack.get(stack.size() - 1);
    }

    public void pushCfFrame(PageContext pageContext, String sourceFilePath) {
        maybe_pushCfFrame_worker(pageContext, sourceFilePath);
    }
    
    private DebugFrame maybe_pushCfFrame_worker(PageContext pageContext, String sourceFilePath) {
        Thread currentThread = Thread.currentThread();

        ArrayList<DebugFrame> stack = cfStackByThread.get(currentThread);

        // The null case means "fresh stack", this is the first frame
        // Frame length shouldn't ever be zero, we should tear it down when it hits zero
        if (stack == null || stack.size() == 0) {
            ArrayList<DebugFrame> list = new ArrayList<>();
            cfStackByThread.put(currentThread, list);
            stack = list;

            pageContextByThread.put(currentThread, new WeakReference<>(pageContext));
        }

        final int depth = stack.size(); // first frame is frame 0, and prior to pushing the first frame the stack is length 0; next frame is frame 1, and prior to pushing it the stack is of length 1, ...
        
        FrameContext maybeBaseFrame = stack.size() == 0
            ? null
            : stack.get(0) instanceof Frame ? ((Frame)stack.get(0)).getFrameContext() : null;

        final DebugFrame frame = DebugFrame.makeFrame(
            sourceFilePath,
            depth,
            valTracker,
            pageContext,
            maybeBaseFrame
        );

        stack.add(frame);

        // if (stepRequestByThread.containsKey(currentThread)) {
        //     System.out.println("pushed frame during active step request:");
        //     System.out.println("  " + frame.getName() + " @ " + frame.getSourceFilePath() + ":" + frame.getLine());
        // }

        frameByFrameID.put(frame.getId(), frame);

        return frame;
    }

    public void pushCfFunctionDefaultValueInitializationFrame(PageContext pageContext, String sourceFilePath) {
        DebugFrame frame = maybe_pushCfFrame_worker(pageContext, sourceFilePath);
        if (frame instanceof Frame) {
            ((Frame)frame).isUdfDefaultValueInitFrame = true;
        }
    }

    public void popCfFrame() {
        Thread currentThread = Thread.currentThread();
        ArrayList<DebugFrame> maybeNull_frameListing = cfStackByThread.get(currentThread);

        if (maybeNull_frameListing == null) {
            // error case, maybe throw
            // we should not be popping from a non-existent thing
            return;
        }

        DebugFrame poppedFrame = null;

        if (maybeNull_frameListing.isEmpty()) {
            System.err.println("[luceedebug] popFrame: frame stack for thread '" + currentThread + "' is empty - ignoring pop");
            return;
        }
        else {
            poppedFrame = maybeNull_frameListing.remove(maybeNull_frameListing.size() - 1);
            frameByFrameID.remove(poppedFrame.getId());
        }

        if (maybeNull_frameListing.size() == 0) {
            // we popped the last frame, so we destroy the whole stack
            cfStackByThread.remove(currentThread);
            pageContextByThread.remove(currentThread);
            
            // TODO: cancel any current thread step requests here (e.g. a "step over" on last line of last frame in current request)
        }
    }

    public String getSourcePathForVariablesRef(int variablesRef) {
        return valTracker
            .maybeGetFromId(variablesRef)
            .map(taggedObj -> CfValueDebuggerBridge.getSourcePath(taggedObj.obj))
            .orElseGet(() -> null);
    }
}
