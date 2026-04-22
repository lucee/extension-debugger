package org.lucee.extension.debugger.strong;

import com.sun.jdi.ThreadReference;

public final class JdwpThreadID extends StrongT<Long> {
    public JdwpThreadID(Long v) {
        super(v);
    }

    public static JdwpThreadID of(ThreadReference v) {
        return new JdwpThreadID(v.uniqueID());
    }
}
