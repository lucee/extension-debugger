package org.lucee.extension.debugger.coreinject;

import lucee.runtime.type.scope.Scope;

/**
 * Intended to be an extension on lucee.runtime.type.scope.ClosureScope, applied during classfile rewrites during agent startup.
 */
public interface ClosureScopeLocalScopeAccessorShim {
    Scope getLocalScope();
}
