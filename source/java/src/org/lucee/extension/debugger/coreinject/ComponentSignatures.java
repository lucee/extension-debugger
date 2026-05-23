package org.lucee.extension.debugger.coreinject;

import java.util.ArrayList;

import lucee.runtime.Component;
import lucee.runtime.PageContext;
import lucee.runtime.exp.PageException;
import lucee.runtime.type.Array;
import lucee.runtime.type.Collection;
import lucee.runtime.type.KeyImpl;
import lucee.runtime.type.Struct;

import org.lucee.extension.debugger.IDebugEntity;

/**
 * Builds the `functions` and `accessors` sub-group entries shown when a
 * Component is expanded in the Variables panel.
 *
 * Both groups read from `cfc.getMetaData(pc).functions`, which lists every
 * function on the component — declared methods AND auto-generated accessors
 * that actually exist (Lucee suppresses entries the property declaration
 * opted out of via `getter="false"` / `setter="false"`).
 *
 * The discriminator is the `position` key: declared functions carry
 * `position:{start,end}` line numbers; auto-generated accessors don't.
 */
class ComponentSignatures {

    private static final Collection.Key K_FUNCTIONS = KeyImpl.init("functions");
    private static final Collection.Key K_NAME = KeyImpl.init("name");
    private static final Collection.Key K_TYPE = KeyImpl.init("type");
    private static final Collection.Key K_RETURNTYPE = KeyImpl.init("returntype");
    private static final Collection.Key K_PARAMETERS = KeyImpl.init("parameters");
    private static final Collection.Key K_REQUIRED = KeyImpl.init("required");
    private static final Collection.Key K_ACCESS = KeyImpl.init("access");
    private static final Collection.Key K_POSITION = KeyImpl.init("position");

    static IDebugEntity[] buildFunctionEntries(Component cfc, PageContext pc) {
        return buildEntries(cfc, pc, true);
    }

    static IDebugEntity[] buildAccessorEntries(Component cfc, PageContext pc) {
        return buildEntries(cfc, pc, false);
    }

    private static IDebugEntity[] buildEntries(Component cfc, PageContext pc, boolean wantDeclared) {
        if (pc == null) return new IDebugEntity[0];
        Struct meta;
        try {
            meta = cfc.getMetaData(pc);
        } catch (PageException e) {
            throw new RuntimeException("getMetaData failed for component " + cfc.getName(), e);
        }
        Array functions = getArrayField(meta, K_FUNCTIONS);
        if (functions == null) return new IDebugEntity[0];
        ArrayList<IDebugEntity> result = new ArrayList<>();
        for (int i = 1; i <= functions.size(); i++) {
            Object item = functions.get(i, null);
            if (!(item instanceof Struct)) continue;
            Struct fn = (Struct) item;
            boolean isDeclared = fn.get(K_POSITION, null) != null;
            if (isDeclared != wantDeclared) continue;
            DebugEntity e = new DebugEntity();
            e.name = getStringField(fn, K_NAME, "?");
            e.value = renderFunctionSignature(fn);
            e.variablesReference = 0;
            result.add(e);
        }
        result.sort((a, b) -> a.getName().compareToIgnoreCase(b.getName()));
        return result.toArray(new IDebugEntity[0]);
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
        if (!"any".equalsIgnoreCase(rt) && !"void".equalsIgnoreCase(rt)) {
            sb.append(" : ").append(rt);
        }
        return sb.toString();
    }

    private static String getStringField(Struct s, Collection.Key k, String defaultValue) {
        Object v = s.get(k, null);
        if (v == null) return defaultValue;
        return (v instanceof String) ? (String) v : v.toString();
    }

    private static boolean getBoolField(Struct s, Collection.Key k, boolean defaultValue) {
        Object v = s.get(k, null);
        if (v == null) return defaultValue;
        if (v instanceof Boolean) return (Boolean) v;
        String str = v.toString();
        return Boolean.parseBoolean(str) || "yes".equalsIgnoreCase(str) || "1".equals(str);
    }

    private static Array getArrayField(Struct s, Collection.Key k) {
        Object v = s.get(k, null);
        return (v instanceof Array) ? (Array) v : null;
    }
}
