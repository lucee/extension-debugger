<cfscript>
/**
 * luceedebug Performance Benchmark
 *
 * This script stresses the hot paths in luceedebug:
 * - Function calls (pushCfFrame/popCfFrame)
 * - Line stepping (luceedebug_stepNotificationEntry_step)
 * - Nested calls and deep stacks
 *
 * Run with JFR enabled to profile overhead.
 */

// Configuration
ITERATIONS = 100000;
NESTED_DEPTH = 10;

// Simple function call - minimal overhead baseline
function simpleFunc( n ) {
	return n + 1;
}

// Recursive function - tests deep call stacks
function recursiveFunc( depth ) {
	if ( depth <= 0 ) {
		return 0;
	}
	return 1 + recursiveFunc( depth - 1 );
}

// Function with multiple lines - stresses line stepping
function multiLineFunc( n ) {
	var a = n;
	var b = a + 1;
	var c = b + 2;
	var d = c + 3;
	var e = d + 4;
	var f = e + 5;
	var g = f + 6;
	var h = g + 7;
	var i = h + 8;
	var j = i + 9;
	return j;
}

// Function that calls other functions - nested calls
function callerFunc( n ) {
	var x = simpleFunc( n );
	var y = multiLineFunc( x );
	return y;
}

// Warmup
systemOutput( "Warming up...", true );
for ( i = 1; i <= 1000; i++ ) {
	simpleFunc( i );
	multiLineFunc( i );
	callerFunc( i );
}

// Benchmark: Simple function calls
systemOutput( "", true );
systemOutput( "=== Benchmark: Simple function calls (#ITERATIONS# iterations) ===", true );
start = getTickCount();
for ( i = 1; i <= ITERATIONS; i++ ) {
	simpleFunc( i );
}
elapsed = getTickCount() - start;
systemOutput( "Time: #elapsed#ms (#ITERATIONS / elapsed * 1000# calls/sec)", true );

// Benchmark: Multi-line function
systemOutput( "", true );
systemOutput( "=== Benchmark: Multi-line function (#ITERATIONS# iterations) ===", true );
start = getTickCount();
for ( i = 1; i <= ITERATIONS; i++ ) {
	multiLineFunc( i );
}
elapsed = getTickCount() - start;
systemOutput( "Time: #elapsed#ms", true );

// Benchmark: Nested calls
systemOutput( "", true );
systemOutput( "=== Benchmark: Nested function calls (#ITERATIONS# iterations) ===", true );
start = getTickCount();
for ( i = 1; i <= ITERATIONS; i++ ) {
	callerFunc( i );
}
elapsed = getTickCount() - start;
systemOutput( "Time: #elapsed#ms", true );

// Benchmark: Deep recursion
systemOutput( "", true );
systemOutput( "=== Benchmark: Recursive calls (depth=#NESTED_DEPTH#, #ITERATIONS# iterations) ===", true );
start = getTickCount();
for ( i = 1; i <= ITERATIONS; i++ ) {
	recursiveFunc( NESTED_DEPTH );
}
elapsed = getTickCount() - start;
systemOutput( "Time: #elapsed#ms", true );

// Benchmark: Mixed workload
systemOutput( "", true );
systemOutput( "=== Benchmark: Mixed workload (#ITERATIONS# iterations) ===", true );
start = getTickCount();
for ( i = 1; i <= ITERATIONS; i++ ) {
	simpleFunc( i );
	multiLineFunc( i );
	callerFunc( i );
	recursiveFunc( 5 );
}
elapsed = getTickCount() - start;
systemOutput( "Time: #elapsed#ms", true );

systemOutput( "", true );
systemOutput( "Benchmark complete!", true );
</cfscript>
