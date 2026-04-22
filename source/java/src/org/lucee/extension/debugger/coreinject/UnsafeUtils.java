package org.lucee.extension.debugger.coreinject;

import lucee.runtime.exp.PageException;
import lucee.runtime.type.Collection;

public class UnsafeUtils {
    @SuppressWarnings("unchecked")
    static <T> T uncheckedCast(Object e) {
        return (T)e;
    }

    @SuppressWarnings("deprecation")
    public static Object deprecatedScopeGet(Collection scope, String key) throws PageException {
        // lucee wants us to use Collection's
        // public Object get(Collection.Key key) throws PageException;
        return scope.get(key);
    }
}
