package org.lucee.extension.debugger.coreinject;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.Date;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;
import java.util.concurrent.TimeUnit;

import org.lucee.extension.debugger.util.ExpiringLruCache;

import lucee.runtime.Component;
import lucee.runtime.PageContext;
import lucee.runtime.type.Array;
import org.lucee.extension.debugger.ICfValueDebuggerBridge;
import org.lucee.extension.debugger.IDebugEntity;
import org.lucee.extension.debugger.coreinject.frame.Frame;

public class CfValueDebuggerBridge implements ICfValueDebuggerBridge {
    // Pin some ephemeral evaluated things so they don't get GC'd immediately.
    // It would be better to pin them to a "session" or something with a meaningful lifetime,
    // rather than hope they live long enough in this cache to be useful.
    // Most objects do not require being pinned here -- objects that require pinning are those we synthetically create
    // while generating debug info, like when we wrap a CFC in a MarkerTrait.Scope, or create an array out of a Query object.
    private static final ExpiringLruCache<Integer, Object> pinnedObjects =
        new ExpiringLruCache<>(50, 10, TimeUnit.MINUTES);
    public static void pin(Object obj) {
        pinnedObjects.put(System.identityHashCode(obj), obj);
    }

    private final Frame frame;
    private final ValTracker valTracker;
    public final Object obj;
    public final long id;

    public CfValueDebuggerBridge(Frame frame, Object obj) {
        this.frame = Objects.requireNonNull(frame);
        this.valTracker = frame.valTracker;
        this.obj = Objects.requireNonNull(obj);
        this.id = frame.valTracker.idempotentRegisterObject(obj).id;
    }

    /**
     * Constructor for use with native Lucee7 debugger frames where we don't have a Frame object.
     * The valTracker is stored directly since we don't have a Frame.
     */
    public CfValueDebuggerBridge(ValTracker valTracker, Object obj) {
        this.frame = null; // Not available for native frames
        this.valTracker = Objects.requireNonNull(valTracker);
        this.obj = Objects.requireNonNull(obj);
        this.id = valTracker.idempotentRegisterObject(obj).id;
    }

    public long getID() {
        return id;
    }

    public static class MarkerTrait {
        public static class Scope {
            public final Map<?,?> scopelike;
            // Case-insensitive set of keys to skip when iterating. Used to hide
            // Lucee's redundant `this`-self-ref inside the variables scope.
            public final java.util.Set<String> ignoreKeys;
            public Scope(Map<?,?> scopelike) {
                this(scopelike, java.util.Collections.emptySet());
            }
            public Scope(Map<?,?> scopelike, java.util.Set<String> ignoreKeys) {
                this.scopelike = scopelike;
                this.ignoreKeys = ignoreKeys;
            }
        }
        // Holds pre-built debug entries (e.g. function signatures derived from getMetaData).
        // Expanded directly without going through getAsMaplike — entries carry their own display.
        public static class PreBuiltGroup {
            public final IDebugEntity[] entries;
            public PreBuiltGroup(IDebugEntity[] entries) {
                this.entries = entries;
            }
        }
    }

    // Resolves a DAP frameId → PageContext. Registered by the mode-specific VM
    // (NativeLuceeVm / LuceeVm) at startup. Used for getMetaData() lookups.
    private static volatile java.util.function.Function<Long, PageContext> pcResolver;

    public static void registerPageContextResolver(java.util.function.Function<Long, PageContext> resolver) {
        pcResolver = resolver;
    }

    private static PageContext resolvePc(Long frameId) {
        if (frameId == null) return null;
        java.util.function.Function<Long, PageContext> r = pcResolver;
        if (r == null) return null;
        try {
            return r.apply(frameId);
        } catch (Throwable t) {
            return null;
        }
    }


    /**
     * @maybeNull_which --> null means "any type"
     */
    public static IDebugEntity[] getAsDebugEntity(Frame frame, Object obj, IDebugEntity.DebugEntityType maybeNull_which) {
        return getAsDebugEntity(frame.valTracker, obj, maybeNull_which, null);
    }

    public static IDebugEntity[] getAsDebugEntity(ValTracker valTracker, Object obj, IDebugEntity.DebugEntityType maybeNull_which) {
        return getAsDebugEntity(valTracker, obj, maybeNull_which, null);
    }

    /**
     * Get debug entities for an object's children.
     * @param valTracker The value tracker
     * @param obj The parent object to expand
     * @param maybeNull_which Filter for named/indexed variables, or null for all
     * @param parentPath The variable path of the parent (e.g., "local.foo"), or null if not tracked
     */
    public static IDebugEntity[] getAsDebugEntity(ValTracker valTracker, Object obj, IDebugEntity.DebugEntityType maybeNull_which, String parentPath) {
        return getAsDebugEntity(valTracker, obj, maybeNull_which, parentPath, null);
    }

    /**
     * Get debug entities for an object's children.
     * @param valTracker The value tracker
     * @param obj The parent object to expand
     * @param maybeNull_which Filter for named/indexed variables, or null for all
     * @param parentPath The variable path of the parent (e.g., "local.foo"), or null if not tracked
     * @param frameId The frame ID for setVariable support, or null if not tracked
     */
    public static IDebugEntity[] getAsDebugEntity(ValTracker valTracker, Object obj, IDebugEntity.DebugEntityType maybeNull_which, String parentPath, Long frameId) {
        final boolean namedOK = maybeNull_which == null || maybeNull_which == IDebugEntity.DebugEntityType.NAMED;
        final boolean indexedOK = maybeNull_which == null || maybeNull_which == IDebugEntity.DebugEntityType.INDEXED;

        if (obj instanceof MarkerTrait.PreBuiltGroup && namedOK) {
            return ((MarkerTrait.PreBuiltGroup) obj).entries;
        }
        if (obj instanceof MarkerTrait.Scope && namedOK) {
            MarkerTrait.Scope scope = (MarkerTrait.Scope) obj;
            @SuppressWarnings("unchecked")
            var m = (Map<String, Object>)(scope.scopelike);
            return getAsMaplike(valTracker, m, true, scope.ignoreKeys, parentPath, frameId);
        }
        else if (obj instanceof Map && namedOK) {
            if (obj instanceof Component) {
                List<IDebugEntity> entries = buildComponentGroupEntries(valTracker, (Component) obj, parentPath, frameId);
                return entries.toArray(new IDebugEntity[0]);
            }
            else {
                @SuppressWarnings("unchecked")
                var m = (Map<String, Object>)obj;
                return getAsMaplike(valTracker, m, parentPath, frameId);
            }
        }
        else if (obj instanceof Array && indexedOK) {
            return getAsCfArray(valTracker, (Array)obj, parentPath, frameId);
        }
        else {
            return new IDebugEntity[0];
        }
    }

    private static Comparator<IDebugEntity> xscopeByName = Comparator.comparing((IDebugEntity v) -> v.getName().toLowerCase());

    /**
     * Check if an object is a "noisy" component function that should be hidden in debug output.
     * Uses class name comparison to avoid ClassNotFoundException in OSGi extension mode.
     */
    private static boolean isNoisyComponentFunction(Object obj) {
        String className = obj.getClass().getName();
        // Discard UDFGetterProperty, UDFSetterProperty, UDFImpl (noisy)
        // But retain Lambda and Closure (useful)
        boolean isNoisyUdf = className.equals("lucee.runtime.type.UDFGetterProperty")
            || className.equals("lucee.runtime.type.UDFSetterProperty")
            || className.equals("lucee.runtime.type.UDFImpl");
        boolean isLambdaOrClosure = className.equals("lucee.runtime.type.Lambda")
            || className.equals("lucee.runtime.type.Closure");
        return isNoisyUdf && !isLambdaOrClosure;
    }

    /**
     * Check class by name to avoid ClassNotFoundException in OSGi extension mode.
     * Some Lucee core classes aren't visible to the extension classloader.
     */
    private static boolean isInstanceOf(Object obj, String className) {
        if (obj == null) return false;
        Class<?> clazz = obj.getClass();
        while (clazz != null) {
            if (clazz.getName().equals(className)) return true;
            // Check interfaces
            for (Class<?> iface : clazz.getInterfaces()) {
                if (iface.getName().equals(className)) return true;
            }
            clazz = clazz.getSuperclass();
        }
        return false;
    }

    /**
     * Build the named-variable sub-groups shown when a Component is expanded:
     * this / variables / static / functions / accessors. Empty groups are omitted.
     * functions/accessors are sourced from cfc.getMetaData(pc); accessors are
     * derived from `properties` because auto-generated UDFs aren't in metadata.functions.
     */
    private static List<IDebugEntity> buildComponentGroupEntries(ValTracker valTracker, Component cfc, String parentPath, Long frameId) {
        List<IDebugEntity> entries = new ArrayList<>();

        // All three scope-shaped sub-groups (this/variables/static) use treatAsScopes=true
        // so their expansion is flat-maplike. Without it, ComponentScope/StaticScope
        // (both `instanceof Component`) recursively re-trigger sub-group rendering.
        if (hasNonNoisyEntries((Map<?,?>) cfc)) {
            entries.add(maybeNull_asValue(valTracker, "this", cfc, true, true, parentPath, frameId));
        }
        Object varsScope = cfc.getComponentScope();
        if (varsScope instanceof Map && hasNonNoisyEntries((Map<?,?>) varsScope)) {
            // `this` is hidden inside variables — Lucee stores a self-ref under that key,
            // which otherwise opens variables → this → variables → ... in an infinite click chain.
            // The cfc's own `this` sub-group at this level is the proper access point.
            entries.add(buildFilteredScopeEntry(valTracker, "variables", (Map<?,?>) varsScope, java.util.Set.of("this"), parentPath, frameId));
        }
        Object staticScope = cfc.staticScope();
        if (staticScope instanceof Map && !((Map<?,?>) staticScope).isEmpty()) {
            entries.add(maybeNull_asValue(valTracker, "static", staticScope, true, true, parentPath, frameId));
        }
        PageContext pc = resolvePc(frameId);
        IDebugEntity[] fnEntries = ComponentSignatures.buildFunctionEntries(cfc, pc);
        if (fnEntries.length > 0) {
            entries.add(buildPreBuiltGroupEntry(valTracker, "functions", fnEntries, parentPath, frameId));
        }
        IDebugEntity[] accEntries = ComponentSignatures.buildAccessorEntries(cfc, pc);
        if (accEntries.length > 0) {
            entries.add(buildPreBuiltGroupEntry(valTracker, "accessors", accEntries, parentPath, frameId));
        }
        return entries;
    }

    private static boolean hasNonNoisyEntries(Map<?, ?> map) {
        for (Map.Entry<?, ?> e : map.entrySet()) {
            Object v = e.getValue();
            if (v == null) return true;
            if (!isNoisyComponentFunction(v)) return true;
        }
        return false;
    }

    private static int countNonNoisy(Map<?, ?> map) {
        int n = 0;
        for (Map.Entry<?, ?> e : map.entrySet()) {
            Object v = e.getValue();
            if (v == null) { n++; continue; }
            if (!isNoisyComponentFunction(v)) n++;
        }
        return n;
    }

    private static IDebugEntity buildFilteredScopeEntry(ValTracker valTracker, String name, Map<?,?> scopelike, java.util.Set<String> ignoreKeys, String parentPath, Long frameId) {
        MarkerTrait.Scope marker = new MarkerTrait.Scope(scopelike, ignoreKeys);
        pin(marker);
        DebugEntity val = new DebugEntity();
        val.name = name;
        int count = 0;
        for (Map.Entry<?, ?> e : scopelike.entrySet()) {
            if (containsIgnoreCase(ignoreKeys, String.valueOf(e.getKey()))) continue;
            Object v = e.getValue();
            if (v == null || !isNoisyComponentFunction(v)) count++;
        }
        val.value = "{} (" + count + " members)";
        val.namedVariables = count;
        String childPath = (parentPath != null) ? parentPath + "." + name : null;
        val.variablesReference = valTracker.registerObjectWithPathAndFrameId(marker, childPath, frameId).id;
        return val;
    }

    private static IDebugEntity buildPreBuiltGroupEntry(ValTracker valTracker, String name, IDebugEntity[] entries, String parentPath, Long frameId) {
        DebugEntity val = new DebugEntity();
        val.name = name;
        val.value = "{} (" + entries.length + " members)";
        val.namedVariables = entries.length;
        String childPath = (parentPath != null) ? parentPath + "." + name : null;
        val.variablesReference = valTracker.registerObjectWithPathAndFrameId(
            new MarkerTrait.PreBuiltGroup(entries), childPath, frameId
        ).id;
        return val;
    }

    private static IDebugEntity[] getAsMaplike(ValTracker valTracker, Map<String, Object> map, String parentPath, Long frameId) {
        return getAsMaplike(valTracker, map, true, java.util.Collections.emptySet(), parentPath, frameId);
    }

    private static IDebugEntity[] getAsMaplike(ValTracker valTracker, Map<String, Object> map, boolean skipNoisyComponentFunctions, java.util.Set<String> ignoreKeys, String parentPath, Long frameId) {
        ArrayList<IDebugEntity> results = new ArrayList<>();

        Set<Map.Entry<String,Object>> entries = map.entrySet();

        for (Map.Entry<String, Object> entry : entries) {
            if (!ignoreKeys.isEmpty() && containsIgnoreCase(ignoreKeys, entry.getKey())) continue;
            IDebugEntity val = maybeNull_asValue(valTracker, entry.getKey(), entry.getValue(), skipNoisyComponentFunctions, false, parentPath, frameId);
            if (val != null) {
                results.add(val);
            }
        }

        // {
        //     DebugEntity val = new DebugEntity();
        //     val.name = "__luceedebugValueID";
        //     val.value = "" + valTracker.idempotentRegisterObject(map).id;
        //     results.add(val);
        // }

        results.sort(xscopeByName);

        return results.toArray(new IDebugEntity[results.size()]);
    }

    private static boolean containsIgnoreCase(java.util.Set<String> set, String key) {
        if (set == null || set.isEmpty()) return false;
        for (String s : set) {
            if (s.equalsIgnoreCase(key)) return true;
        }
        return false;
    }

    private static IDebugEntity[] getAsCfArray(ValTracker valTracker, Array array, String parentPath, Long frameId) {
        ArrayList<IDebugEntity> result = new ArrayList<>();

        // cf 1-indexed
        for (int i = 1; i <= array.size(); ++i) {
            IDebugEntity val = maybeNull_asValue(valTracker, Integer.toString(i), array.get(i, null), parentPath, frameId);
            if (val != null) {
                result.add(val);
            }
        }

        return result.toArray(new IDebugEntity[result.size()]);
    }

    public IDebugEntity maybeNull_asValue(String name) {
        return maybeNull_asValue(valTracker, name, obj, true, false, null, null);
    }

    /**
     * returns null for "this should not be displayed as a debug entity", which sort of a kludgy way
     * to clean up cfc value info.
     * which is used to cut down on noise from CFC getters/setters/member-functions which aren't too useful for debugging.
     * Maybe such things should be optionally included as per some configuration.
     */
    private static IDebugEntity maybeNull_asValue(ValTracker valTracker, String name, Object obj, String parentPath, Long frameId) {
        return maybeNull_asValue(valTracker, name, obj, true, false, parentPath, frameId);
    }

    /**
     * @markDiscoveredComponentsAsIterableThisRef if true, a Component will be marked as if it were any normal Map<String, Object>. This drives discovery of variables;
     * showing the "top level" of a component we want to show its "inner scopes" (this, variables, and static)
     * @param parentPath The variable path of the parent container (e.g., "local"), or null if not tracked
     * @param frameId The frame ID for setVariable support, or null if not tracked
     */
    private static IDebugEntity maybeNull_asValue(
        ValTracker valTracker,
        String name,
        Object obj,
        boolean skipNoisyComponentFunctions,
        boolean treatDiscoveredComponentsAsScopes,
        String parentPath,
        Long frameId
    ) {
        // Build the full path for this variable
        String childPath = (parentPath != null) ? parentPath + "." + name : null;
        DebugEntity val = new DebugEntity();
        val.name = name;

        if (obj == null) {
            val.value = "<<java-null>>";
        }
        else if (obj instanceof String) {
            val.value = "\"" + obj + "\"";
        }
        else if (obj instanceof Number) {
            val.value = obj.toString();
        }
        else if (obj instanceof Boolean) {
            val.value = obj.toString();
        }
        else if (obj instanceof Date) {
            val.value = obj.toString();
        }
        else if (obj instanceof Array) {
            int len = ((Array)obj).size();
            val.value = "Array (" + len + ")";
            val.indexedVariables = len;
            val.variablesReference = valTracker.registerObjectWithPathAndFrameId(obj, childPath, frameId).id;
        }
        else if (
            /*
                // retain the lambbda/closure types
                var lambda = () => {} // lucee.runtime.type.Lambda
                var closure = function() {} // lucee.runtime.type.Closure

                // discard component function types, they're mostly noise in debug output
                component accessors=true {
                    property name="foo"; // lucee.runtime.type.UDFGetterProperty / lucee.runtime.type.UDFSetterProperty
                    function foo() {} // lucee.runtime.type.UDFImpl
                }
            */
            skipNoisyComponentFunctions
            && isNoisyComponentFunction(obj)
        ) {
            return null;
        }
        else if (isInstanceOf(obj, "lucee.runtime.type.QueryImpl")) {
            // Handle Query - use reflection to avoid ClassNotFoundException in OSGi
            try {
                Method toQueryArrayMethod = Class.forName("lucee.runtime.type.query.QueryArray", true, obj.getClass().getClassLoader())
                    .getMethod("toQueryArray", Class.forName("lucee.runtime.type.QueryImpl", true, obj.getClass().getClassLoader()));
                Object queryAsArrayOfStructs = toQueryArrayMethod.invoke(null, obj);
                Method sizeMethod = queryAsArrayOfStructs.getClass().getMethod("size");
                int size = (int) sizeMethod.invoke(queryAsArrayOfStructs);
                val.value = "Query (" + size + " rows)";

                pin(queryAsArrayOfStructs);

                val.variablesReference = valTracker.registerObjectWithPathAndFrameId(queryAsArrayOfStructs, childPath, frameId).id;
            }
            catch (Throwable e) {
                // Fall back to generic display
                try {
                    val.value = obj.toString();
                    val.variablesReference = valTracker.registerObjectWithPathAndFrameId(obj, childPath, frameId).id;
                }
                catch (Throwable x) {
                    val.value = "<?> (no string representation available)";
                    val.variablesReference = 0;
                }
            }
        }
        else if (obj instanceof Map) {
            if (obj instanceof Component) {
                val.value = "cfc<" + ((Component)obj).getName() + ">";
                if (treatDiscoveredComponentsAsScopes) {
                    var v = new MarkerTrait.Scope((Component)obj);
                    // agent-mode ComponentImpl has the shim mixed in via bytecode; native mode doesn't
                    if (obj instanceof ComponentScopeMarkerTraitShim) {
                        ((ComponentScopeMarkerTraitShim)obj).__luceedebug__pinComponentScopeMarkerTrait(v);
                    } else {
                        pin(v);
                    }
                    // wrap expands flat via the Scope branch — count non-noisy public members
                    val.namedVariables = countNonNoisy((Map<?,?>) obj);
                    val.variablesReference = valTracker.registerObjectWithPathAndFrameId(v, childPath, frameId).id;
                }
                else {
                    // 5 = upper bound (this/variables/static/functions/accessors); real groups materialise on expand
                    val.namedVariables = 5;
                    val.variablesReference = valTracker.registerObjectWithPathAndFrameId(obj, childPath, frameId).id;
                }
            }
            else {
                int len = ((Map<?,?>)obj).size();
                val.value = "{} (" + len + " members)";
                val.namedVariables = len;
                val.variablesReference = valTracker.registerObjectWithPathAndFrameId(obj, childPath, frameId).id;
            }
        }
        else {
            try {
                val.value = obj.toString();
                val.variablesReference = valTracker.registerObjectWithPathAndFrameId(obj, childPath, frameId).id;
            }
            catch (Throwable x) {
                val.value = "<?> (no string representation available)";
                val.variablesReference = 0;
            }
        }

        return val;
    }

    public int getNamedVariablesCount() {
        if (obj instanceof Map) {
            return ((Map<?,?>)obj).size();
        }
        else {
            return 0;
        }
    }

    public int getIndexedVariablesCount() {
        if (isInstanceOf(obj, "lucee.runtime.type.scope.Argument")) {
            // `arguments` scope is both an Array and a Map, which represents the possiblity that a function is called with named args or positional args.
            // It seems like saner default behavior to report it only as having named variables, and zero indexed variables.
            return 0;
        }
        else if (obj instanceof Array) {
            return ((Array)obj).size();
        }
        else {
            return 0;
        }
    }

    /**
     * @return String, or null if there is no path for the underlying entity
     */
    public static String getSourcePath(Object obj) {
        if (obj instanceof Component) {
            return ((Component)obj).getPageSource().getPhyscalFile().getAbsolutePath();
        }
        else if (isInstanceOf(obj, "lucee.runtime.type.UDFImpl")) {
            // Use reflection to avoid ClassNotFoundException in OSGi
            try {
                Field propsField = obj.getClass().getField("properties");
                Object props = propsField.get(obj);
                Method getPageSourceMethod = props.getClass().getMethod("getPageSource");
                Object pageSource = getPageSourceMethod.invoke(props);
                Method getPhyscalFileMethod = pageSource.getClass().getMethod("getPhyscalFile");
                Object file = getPhyscalFileMethod.invoke(pageSource);
                Method getAbsolutePathMethod = file.getClass().getMethod("getAbsolutePath");
                return (String) getAbsolutePathMethod.invoke(file);
            } catch (Throwable e) {
                return null;
            }
        }
        else if (isInstanceOf(obj, "lucee.runtime.type.UDFGSProperty")) {
            // Use reflection to avoid ClassNotFoundException in OSGi
            try {
                Method getPageSourceMethod = obj.getClass().getMethod("getPageSource");
                Object pageSource = getPageSourceMethod.invoke(obj);
                Method getPhyscalFileMethod = pageSource.getClass().getMethod("getPhyscalFile");
                Object file = getPhyscalFileMethod.invoke(pageSource);
                Method getAbsolutePathMethod = file.getClass().getMethod("getAbsolutePath");
                return (String) getAbsolutePathMethod.invoke(file);
            } catch (Throwable e) {
                return null;
            }
        }
        else {
            return null;
        }
    }
}
