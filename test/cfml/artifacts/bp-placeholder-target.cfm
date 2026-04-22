<cfscript>
/**
 * Dedicated target file for agent-mode placeholder-state assertions in
 * BreakpointsTest (testSetBreakpointReturnsVerified, testSetMultipleBreakpoints).
 *
 * Purpose: guarantees the file's $cf class is UNCOMPILED when those tests
 * run, regardless of test-method execution order (which TestBox / Lucee
 * reflection orders differently across versions). Uncompiled state is what
 * makes agent mode return `verified:false` + id — the contract those tests
 * assert on.
 *
 * DO NOT TRIGGER THIS FILE from any test. Do not let any afterEach hit it.
 * If any test touches it, the class compiles and the placeholder assertions
 * start returning `verified:true`, breaking the tests.
 *
 * The flip from verified:false → verified:true via the `breakpoint` changed
 * event is tested end-to-end by DelayedVerifyTest against its own target.
 */
var marker = "placeholder";
writeOutput( marker );
</cfscript>
