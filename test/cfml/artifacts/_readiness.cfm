<cfscript>
// Dedicated readiness-probe target for the CI workflow's "Wait for debuggee
// to be ready" step. Purpose: verify the webapp mount + Lucee engine are
// serving artifacts, WITHOUT incidentally pre-compiling any test's target
// file. Several tests (see BreakpointsTest.testSetBreakpointReturnsVerified)
// assert agent-mode placeholder behaviour that only holds while the target
// class is uncompiled. If the readiness probe compiles a test target as a
// side effect, those assertions fail in CI but pass locally.
//
// Keep this file minimal. Do not import. Do not include anything. Do not
// let any test set a breakpoint on it.
writeOutput( "ok" );
</cfscript>
