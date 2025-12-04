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

	/**
	 * Log level for debugger output.
	 */
	public enum LogLevel {
		ERROR(0),
		INFO(1),
		DEBUG(2);

		private final int level;

		LogLevel(int level) {
			this.level = level;
		}

		public boolean isEnabled(LogLevel threshold) {
			return this.level <= threshold.level;
		}
	}

	// Cached log level - read once from env
	private static LogLevel cachedLogLevel = null;

	/**
	 * Get log level from environment/system property.
	 * Checks "lucee.debugger.loglevel" / "LUCEE_DEBUGGER_LOGLEVEL".
	 * Valid values: error, info, debug (case-insensitive)
	 * Default: info
	 *
	 * @return the log level
	 */
	public static LogLevel getLogLevel() {
		if (cachedLogLevel != null) {
			return cachedLogLevel;
		}
		String level = getSystemPropOrEnvVar("lucee.debugger.loglevel");
		if (level == null || level.isEmpty()) {
			cachedLogLevel = LogLevel.INFO;
		} else if ("debug".equalsIgnoreCase(level)) {
			cachedLogLevel = LogLevel.DEBUG;
		} else if ("error".equalsIgnoreCase(level)) {
			cachedLogLevel = LogLevel.ERROR;
		} else {
			cachedLogLevel = LogLevel.INFO;
		}
		return cachedLogLevel;
	}

	/**
	 * Check if debug logging is enabled.
	 * @return true if log level is DEBUG
	 */
	public static boolean isDebugLoggingEnabled() {
		return getLogLevel() == LogLevel.DEBUG;
	}
}
