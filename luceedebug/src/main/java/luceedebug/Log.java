package luceedebug;

import org.eclipse.lsp4j.debug.OutputEventArguments;
import org.eclipse.lsp4j.debug.OutputEventArgumentsCategory;
import org.eclipse.lsp4j.debug.services.IDebugProtocolClient;

/**
 * Centralized logging for luceedebug.
 * Routes all log messages through a common method that:
 * - Writes to System.out with [luceedebug] prefix
 * - Optionally sends to DAP OutputEvent when a client is connected
 */
public class Log {
	private static final String PREFIX = "[luceedebug] ";

	// DAP client for sending OutputEvents (set when client connects)
	private static volatile IDebugProtocolClient dapClient = null;

	/**
	 * Set the DAP client to receive log messages as OutputEvents.
	 * Pass null to disable DAP output (e.g., on disconnect).
	 */
	public static void setDapClient(IDebugProtocolClient client) {
		dapClient = client;
	}

	/**
	 * Log a message to console and optionally to DAP client.
	 */
	public static void info(String message) {
		String prefixed = PREFIX + message;
		System.out.println(prefixed);
		sendToDap(message, OutputEventArgumentsCategory.CONSOLE);
	}

	/**
	 * Log an error message.
	 */
	public static void error(String message) {
		String prefixed = PREFIX + "ERROR: " + message;
		System.out.println(prefixed);
		sendToDap("ERROR: " + message, OutputEventArgumentsCategory.STDERR);
	}

	/**
	 * Log an error with exception.
	 */
	public static void error(String message, Throwable t) {
		error(message + ": " + t.getMessage());
		t.printStackTrace();
	}

	/**
	 * Log a debug message (only to console, not to DAP).
	 * Only printed if LUCEE_DEBUGGER_LOGLEVEL=debug.
	 */
	public static void debug(String message) {
		if (EnvUtil.isDebugLoggingEnabled()) {
			System.out.println(PREFIX + "DEBUG: " + message);
		}
	}

	/**
	 * Send log to DAP client if connected.
	 */
	private static void sendToDap(String message, String category) {
		IDebugProtocolClient client = dapClient;
		if (client != null) {
			try {
				var args = new OutputEventArguments();
				args.setCategory(category);
				args.setOutput("[luceedebug] " + message + "\n");
				client.output(args);
			} catch (Exception e) {
				// Don't recursively log - just print to console
				System.out.println(PREFIX + "Failed to send to DAP: " + e.getMessage());
			}
		}
	}
}
