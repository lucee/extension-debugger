package org.lucee.extension.debugger;

public interface IBreakpoint {
    public int getLine();

    public int getID();

    public boolean getIsBound();
}
