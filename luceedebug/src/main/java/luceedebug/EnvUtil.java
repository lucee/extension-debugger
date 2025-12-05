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
	 * Get debugger secret from environment/system property.
	 * Checks "lucee.debugger.secret" / "LUCEE_DEBUGGER_SECRET".
	 *
	 * @return the secret, or null if not set (debugger disabled)
	 */
	public static String getDebuggerSecret() {
		String secret = getSystemPropOrEnvVar("lucee.debugger.secret");
		if (secret != null && !secret.trim().isEmpty()) {
			return secret.trim();
		}
		return null;
	}

	/**
	 * Check if debugger is enabled (secret is set).
	 *
	 * @return true if debugger secret is configured
	 */
	public static boolean isDebuggerEnabled() {
		return getDebuggerSecret() != null;
	}

	/**
	 * Get debugger port from environment/system property.
	 * Checks "lucee.debugger.port" / "LUCEE_DEBUGGER_PORT".
	 * Defaults to 9999 if secret is set but port is not.
	 *
	 * @return the port number, or -1 if debugger disabled (no secret)
	 */
	public static int getDebuggerPort() {
		// No port if no secret
		if (getDebuggerSecret() == null) {
			return -1;
		}
		String port = getSystemPropOrEnvVar("lucee.debugger.port");
		if (port == null || port.isEmpty()) {
			return 9999; // default port
		}
		try {
			return Integer.parseInt(port);
		} catch (NumberFormatException e) {
			return 9999;
		}
	}
}
