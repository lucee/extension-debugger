package org.lucee.extension.debugger.testutils;

public class Utils {
	public static <T> T unreachable() {
		throw new RuntimeException("unreachable");
	}
}
