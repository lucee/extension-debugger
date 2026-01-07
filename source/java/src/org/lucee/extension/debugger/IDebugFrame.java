package org.lucee.extension.debugger;

public interface IDebugFrame {
    public String getSourceFilePath();
    public long getId();
    public String getName();
    public int getDepth();
    public int getLine();
    public void setLine(int line);
    public IDebugEntity[] getScopes();
}
