package luceedebug;

/**
 * Utility class for reading environment variables and system properties
 * in Lucee's naming convention.
 */
public final class EnvUtil {

	private EnvUtil() {}

	/**
	 * Get system property or environment variable.
	 * System property takes precedence. Env var name is derived from property name
	 * by uppercasing and replacing dots with underscores.
	 *
	 * @param propertyName e.g. "lucee.debugger.enabled"
	 * @return the value, or null if not set
	 */
	public static String getSystemPropOrEnvVar(String propertyName) {
		// Try system property first
		String value = System.getProperty(propertyName);
		if (value != null && !value.isEmpty()) {
			return value;
		}
		// Try env var (lucee.debugger.port -> LUCEE_DEBUGGER_PORT)
		String envName = propertyName.toUpperCase().replace('.', '_');
		return System.getenv(envName);
	}

	/**
	 * Check if debugger is enabled via environment variable or system property.
	 * Checks "lucee.debugger.enabled" / "LUCEE_DEBUGGER_ENABLED".
	 *
	 * @return true if debugger is enabled
	 */
	public static boolean isDebuggerEnabled() {
		String value = getSystemPropOrEnvVar("lucee.debugger.enabled");
		return "true".equalsIgnoreCase(value) || "yes".equalsIgnoreCase(value) || "1".equals(value);
	}

	/**
	 * Get debugger port from environment/system property.
	 * Checks "lucee.debugger.port" / "LUCEE_DEBUGGER_PORT".
	 *
	 * @return the port number, or -1 if not set (debugger disabled)
	 */
	public static int getDebuggerPort() {
		String port = getSystemPropOrEnvVar("lucee.debugger.port");
		if (port == null || port.isEmpty()) {
			return -1;
		}
		try {
			return Integer.parseInt(port);
		} catch (NumberFormatException e) {
			return -1;
		}
	}
}
