/**
 * DAP (Debug Adapter Protocol) client for testing luceedebug.
 *
 * Usage:
 *   dap = new DapClient();
 *   dap.connect( "localhost", 10000 );
 *   dap.initialize();
 *   dap.setBreakpoints( "/path/to/file.cfm", [ 10, 20 ] );
 *   dap.configurationDone();
 *   // ... trigger breakpoint via HTTP ...
 *   event = dap.waitForEvent( "stopped", 5000 );
 *   stack = dap.stackTrace( event.body.threadId );
 *   dap.continueThread( event.body.threadId );
 *   dap.disconnect();
 */
component {

	variables.socket = javacast( "null", 0 );
	variables.inputStream = javacast( "null", 0 );
	variables.outputStream = javacast( "null", 0 );
	variables.seq = 0;
	variables.eventQueue = [];
	variables.pendingResponses = {};
	variables.debug = false;

	public function init( boolean debug = false ) {
		variables.debug = arguments.debug;
		return this;
	}

	// ========== Connection ==========

	public function connect( required string host, required numeric port ) {
		variables.socket = createObject( "java", "java.net.Socket" ).init( arguments.host, arguments.port );
		variables.socket.setSoTimeout( 100 ); // 100ms read timeout for polling
		variables.inputStream = variables.socket.getInputStream();
		variables.outputStream = variables.socket.getOutputStream();
		log( "Connected to #arguments.host#:#arguments.port#" );
	}

	public function disconnect() {
		if ( !isNull( variables.socket ) ) {
			variables.socket.close();
			variables.socket = javacast( "null", 0 );
			log( "Disconnected" );
		}
	}

	public boolean function isConnected() {
		return !isNull( variables.socket ) && variables.socket.isConnected() && !variables.socket.isClosed();
	}

	// ========== DAP Commands ==========

	public struct function initialize() {
		var response = sendRequest( "initialize", {
			"clientID": "cfml-dap-test",
			"adapterID": "luceedebug",
			"pathFormat": "path",
			"linesStartAt1": true,
			"columnsStartAt1": true
		} );
		return response;
	}

	public struct function setBreakpoints( required string path, required array lines ) {
		var breakpoints = [];
		for ( var line in arguments.lines ) {
			breakpoints.append( { "line": line } );
		}
		var response = sendRequest( "setBreakpoints", {
			"source": { "path": arguments.path },
			"breakpoints": breakpoints
		} );
		return response;
	}

	public struct function configurationDone() {
		return sendRequest( "configurationDone", {} );
	}

	public struct function threads() {
		return sendRequest( "threads", {} );
	}

	public struct function stackTrace( required numeric threadId, numeric startFrame = 0, numeric levels = 20 ) {
		return sendRequest( "stackTrace", {
			"threadId": arguments.threadId,
			"startFrame": arguments.startFrame,
			"levels": arguments.levels
		} );
	}

	public struct function scopes( required numeric frameId ) {
		return sendRequest( "scopes", {
			"frameId": arguments.frameId
		} );
	}

	public struct function getVariables( required numeric variablesReference ) {
		return sendRequest( "variables", {
			"variablesReference": arguments.variablesReference
		} );
	}

	public struct function continueThread( required numeric threadId ) {
		return sendRequest( "continue", {
			"threadId": arguments.threadId
		} );
	}

	public struct function stepOver( required numeric threadId ) {
		return sendRequest( "next", {
			"threadId": arguments.threadId
		} );
	}

	public struct function stepIn( required numeric threadId ) {
		return sendRequest( "stepIn", {
			"threadId": arguments.threadId
		} );
	}

	public struct function stepOut( required numeric threadId ) {
		return sendRequest( "stepOut", {
			"threadId": arguments.threadId
		} );
	}

	public struct function evaluate( required numeric frameId, required string expression ) {
		return sendRequest( "evaluate", {
			"frameId": arguments.frameId,
			"expression": arguments.expression,
			"context": "watch"
		} );
	}

	public struct function dapDisconnect() {
		return sendRequest( "disconnect", {} );
	}

	// ========== Event Handling ==========

	/**
	 * Wait for a specific event type.
	 * @eventType The event type to wait for (e.g., "stopped", "thread")
	 * @timeoutMs Maximum time to wait in milliseconds
	 * @return The event struct, or throws if timeout
	 */
	public struct function waitForEvent( required string eventType, numeric timeoutMs = 5000 ) {
		var startTime = getTickCount();

		while ( getTickCount() - startTime < arguments.timeoutMs ) {
			// Check queued events first
			for ( var i = 1; i <= variables.eventQueue.len(); i++ ) {
				if ( variables.eventQueue[ i ].event == arguments.eventType ) {
					var event = variables.eventQueue[ i ];
					variables.eventQueue.deleteAt( i );
					return event;
				}
			}

			// Poll for new messages
			pollMessages();
			sleep( 10 );
		}

		throw( type="DapClient.Timeout", message="Timeout waiting for event: #arguments.eventType#" );
	}

	/**
	 * Check if any events of a type are queued.
	 */
	public boolean function hasEvent( required string eventType ) {
		pollMessages();
		for ( var event in variables.eventQueue ) {
			if ( event.event == arguments.eventType ) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Get all queued events (clears the queue).
	 */
	public array function drainEvents() {
		pollMessages();
		var events = variables.eventQueue;
		variables.eventQueue = [];
		return events;
	}

	// ========== Protocol Implementation ==========

	private struct function sendRequest( required string command, required struct args ) {
		var requestSeq = ++variables.seq;
		var request = {
			"seq": requestSeq,
			"type": "request",
			"command": arguments.command,
			"arguments": arguments.args
		};

		sendMessage( request );

		// Wait for response with matching request_seq
		var startTime = getTickCount();
		var timeout = 10000; // 10 second timeout for responses

		while ( getTickCount() - startTime < timeout ) {
			pollMessages();

			if ( variables.pendingResponses.keyExists( requestSeq ) ) {
				var response = variables.pendingResponses[ requestSeq ];
				variables.pendingResponses.delete( requestSeq );

				if ( !response.success ) {
					throw( type="DapClient.Error", message="DAP error: #response.message ?: 'unknown'#" );
				}

				return response;
			}

			sleep( 10 );
		}

		throw( type="DapClient.Timeout", message="Timeout waiting for response to: #arguments.command#" );
	}

	private void function sendMessage( required struct message ) {
		var json = serializeJSON( arguments.message );
		var bytes = json.getBytes( "UTF-8" );
		var header = "Content-Length: #bytes.length#\r\n\r\n";

		log( ">>> #json#" );

		variables.outputStream.write( header.getBytes( "UTF-8" ) );
		variables.outputStream.write( bytes );
		variables.outputStream.flush();
	}

	private void function pollMessages() {
		try {
			while ( variables.inputStream.available() > 0 ) {
				var message = readMessage();
				if ( !isNull( message ) ) {
					handleMessage( message );
				}
			}
		} catch ( any e ) {
			// Socket timeout is expected, ignore
			if ( !e.message contains "timed out" && !e.message contains "Read timed out" ) {
				rethrow;
			}
		}
	}

	private any function readMessage() {
		// Read headers until empty line
		var headers = {};
		var headerLine = readLine();

		while ( headerLine != "" ) {
			var colonPos = headerLine.find( ":" );
			if ( colonPos > 0 ) {
				var key = headerLine.left( colonPos - 1 ).trim();
				var value = headerLine.mid( colonPos + 1, headerLine.len() ).trim();
				headers[ key ] = value;
			}
			headerLine = readLine();
		}

		if ( !headers.keyExists( "Content-Length" ) ) {
			return javacast( "null", 0 );
		}

		// Read body
		var contentLength = val( headers[ "Content-Length" ] );
		var bodyBytes = createObject( "java", "java.io.ByteArrayOutputStream" ).init();
		var remaining = contentLength;

		while ( remaining > 0 ) {
			var b = variables.inputStream.read();
			if ( b == -1 ) {
				throw( type="DapClient.Error", message="Unexpected end of stream" );
			}
			bodyBytes.write( b );
			remaining--;
		}

		var json = bodyBytes.toString( "UTF-8" );
		log( "<<< #json#" );

		return deserializeJSON( json );
	}

	private string function readLine() {
		var line = createObject( "java", "java.lang.StringBuilder" ).init();
		var prevChar = 0;

		while ( true ) {
			var b = variables.inputStream.read();
			if ( b == -1 ) {
				break;
			}
			var c = chr( b );
			if ( c == chr( 10 ) ) { // LF
				break;
			}
			if ( c != chr( 13 ) ) { // Skip CR
				line.append( c );
			}
		}

		return line.toString();
	}

	private void function handleMessage( required struct message ) {
		switch ( arguments.message.type ) {
			case "response":
				variables.pendingResponses[ arguments.message.request_seq ] = arguments.message;
				break;
			case "event":
				variables.eventQueue.append( arguments.message );
				break;
			default:
				log( "Unknown message type: #arguments.message.type#" );
		}
	}

	private void function log( required string msg ) {
		if ( variables.debug ) {
			systemOutput( "[DapClient] #arguments.msg#", true );
		}
	}

}
