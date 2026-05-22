package org.lucee.extension.debugger.coreinject;

import java.util.ArrayList;

import lucee.runtime.Component;
import lucee.runtime.PageContext;
import lucee.runtime.type.Array;
import lucee.runtime.type.Collection;
import lucee.runtime.type.KeyImpl;
import lucee.runtime.type.Struct;

import org.lucee.extension.debugger.IDebugEntity;

/**
 * Builds the `functions` and `accessors` sub-group entries shown when a
 * Component is expanded in the Variables panel.
 *
 * Functions come from cfc.getMetaData(pc).functions and render with their
 * declared signature. Accessors are derived from metadata.properties because
 * auto-generated UDFs aren't listed in metadata.functions — but their
 * signature is predictable from the property declaration
 * (`property name="foo" type="string"` → `getFoo() : string`,
 * `setFoo(required string foo)`).
 */
class ComponentSignatures {

    private static final Collection.Key K_FUNCTIONS = KeyImpl.init("functions");
    private static final Collection.Key K_PROPERTIES = KeyImpl.init("properties");
    private static final Collection.Key K_ACCESSORS = KeyImpl.init("accessors");
    private static final Collection.Key K_NAME = KeyImpl.init("name");
    private static final Collection.Key K_TYPE = KeyImpl.init("type");
    private static final Collection.Key K_RETURNTYPE = KeyImpl.init("returntype");
    private static final Collection.Key K_PARAMETERS = KeyImpl.init("parameters");
    private static final Collection.Key K_REQUIRED = KeyImpl.init("required");
    private static final Collection.Key K_ACCESS = KeyImpl.init("access");
    private static final Collection.Key K_GETTER = KeyImpl.init("getter");
    private static final Collection.Key K_SETTER = KeyImpl.init("setter");

    static IDebugEntity[] buildFunctionEntries(Component cfc, PageContext pc) {
        if (pc == null) return new IDebugEntity[0];
        try {
            Struct meta = cfc.getMetaData(pc);
            Array functions = getArrayField(meta, K_FUNCTIONS);
            if (functions == null) return new IDebugEntity[0];
            ArrayList<IDebugEntity> result = new ArrayList<>();
            for (int i = 1; i <= functions.size(); i++) {
                Object item = functions.get(i, null);
                if (!(item instanceof Struct)) continue;
                Struct fn = (Struct) item;
                DebugEntity e = new DebugEntity();
                e.name = getStringField(fn, K_NAME, "?");
                e.value = renderFunctionSignature(fn);
                e.variablesReference = 0;
                result.add(e);
            }
            result.sort((a, b) -> a.getName().compareToIgnoreCase(b.getName()));
            return result.toArray(new IDebugEntity[0]);
        } catch (Throwable t) {
            return new IDebugEntity[0];
        }
    }

    static IDebugEntity[] buildAccessorEntries(Component cfc, PageContext pc) {
        if (pc == null) return new IDebugEntity[0];
        try {
            Struct meta = cfc.getMetaData(pc);
            boolean componentAccessors = getBoolField(meta, K_ACCESSORS, false);
            Array properties = getArrayField(meta, K_PROPERTIES);
            if (properties == null) return new IDebugEntity[0];
            ArrayList<IDebugEntity> result = new ArrayList<>();
            for (int i = 1; i <= properties.size(); i++) {
                Object item = properties.get(i, null);
                if (!(item instanceof Struct)) continue;
                Struct prop = (Struct) item;
                String pname = getStringField(prop, K_NAME, "");
                if (pname.isEmpty()) continue;
                String ptype = getStringField(prop, K_TYPE, "any");
                // Per-property getter/setter defaults to the component-level accessors flag.
                boolean hasGetter = getBoolField(prop, K_GETTER, componentAccessors);
                boolean hasSetter = getBoolField(prop, K_SETTER, componentAccessors);
                String cap = capitalise(pname);
                if (hasGetter) {
                    DebugEntity g = new DebugEntity();
                    g.name = "get" + cap;
                    g.value = "function get" + cap + "() : " + ptype;
                    g.variablesReference = 0;
                    result.add(g);
                }
                if (hasSetter) {
                    DebugEntity s = new DebugEntity();
                    s.name = "set" + cap;
                    s.value = "function set" + cap + "(required " + ptype + " " + pname + ")";
                    s.variablesReference = 0;
                    result.add(s);
                }
            }
            result.sort((a, b) -> a.getName().compareToIgnoreCase(b.getName()));
            return result.toArray(new IDebugEntity[0]);
        } catch (Throwable t) {
            return new IDebugEntity[0];
        }
    }

    private static String renderFunctionSignature(Struct fn) {
        StringBuilder sb = new StringBuilder();
        String access = getStringField(fn, K_ACCESS, "");
        if (!access.isEmpty() && !"public".equalsIgnoreCase(access)) {
            sb.append(access).append(" ");
        }
        sb.append("function ").append(getStringField(fn, K_NAME, "?")).append("(");
        Array params = getArrayField(fn, K_PARAMETERS);
        if (params != null) {
            for (int i = 1; i <= params.size(); i++) {
                if (i > 1) sb.append(", ");
                Object p = params.get(i, null);
                if (p instanceof Struct) {
                    Struct param = (Struct) p;
                    if (getBoolField(param, K_REQUIRED, false)) sb.append("required ");
                    sb.append(getStringField(param, K_TYPE, "any"))
                        .append(" ")
                        .append(getStringField(param, K_NAME, "?"));
                }
            }
        }
        sb.append(")");
        String rt = getStringField(fn, K_RETURNTYPE, "any");
        if (!"any".equalsIgnoreCase(rt)) sb.append(" : ").append(rt);
        return sb.toString();
    }

    private static String getStringField(Struct s, Collection.Key k, String defaultValue) {
        try {
            Object v = s.get(k, null);
            if (v == null) return defaultValue;
            return (v instanceof String) ? (String) v : v.toString();
        } catch (Throwable t) {
            return defaultValue;
        }
    }

    private static boolean getBoolField(Struct s, Collection.Key k, boolean defaultValue) {
        try {
            Object v = s.get(k, null);
            if (v == null) return defaultValue;
            if (v instanceof Boolean) return (Boolean) v;
            String str = v.toString();
            return Boolean.parseBoolean(str) || "yes".equalsIgnoreCase(str) || "1".equals(str);
        } catch (Throwable t) {
            return defaultValue;
        }
    }

    private static Array getArrayField(Struct s, Collection.Key k) {
        try {
            Object v = s.get(k, null);
            return (v instanceof Array) ? (Array) v : null;
        } catch (Throwable t) {
            return null;
        }
    }

    private static String capitalise(String s) {
        if (s == null || s.isEmpty()) return s;
        return Character.toUpperCase(s.charAt(0)) + s.substring(1);
    }
}
