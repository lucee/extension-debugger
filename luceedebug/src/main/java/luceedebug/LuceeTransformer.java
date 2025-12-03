package luceedebug;

import java.lang.instrument.*;
import java.lang.reflect.Method;

import org.objectweb.asm.*;

import java.security.ProtectionDomain;
import java.util.ArrayList;

public class LuceeTransformer implements ClassFileTransformer {
    private final String jdwpHost;
    private final int jdwpPort;
    private final String debugHost;
    private final int debugPort;
    private final Config config;

    static public class ClassInjection {
        final String name;
        final byte[] bytes;
        ClassInjection(String name, byte[] bytes) {
            this.name = name;
            this.bytes = bytes;
        }
    }

    /**
     * if non-null, we are awaiting the initial class load of PageContextImpl
     * When that happens, these classes will be injected into that class loader.
     * Then, this should be set to null, since we don't need to hold onto them locally.
     */
    private ClassInjection[] pendingCoreLoaderClassInjections;

    public LuceeTransformer(
        ClassInjection[] injections,
        String jdwpHost,
        int jdwpPort,
        String debugHost,
        int debugPort,
        Config config
    ) {
        this.pendingCoreLoaderClassInjections = injections;

        this.jdwpHost = jdwpHost;
        this.jdwpPort = jdwpPort;
        this.debugHost = debugHost;
        this.debugPort = debugPort;
        this.config = config;
    }

    public byte[] transform(ClassLoader loader,
        String className,
        Class<?> classBeingRedefined,
        ProtectionDomain protectionDomain,
        byte[] classfileBuffer
    ) throws IllegalClassFormatException {
        try {
            var classReader = new ClassReader(classfileBuffer);
            String superClass = classReader.getSuperName();

            if (className.equals("lucee/runtime/type/scope/ClosureScope")) {
                return instrumentClosureScope(classfileBuffer);
            }
            else if (className.equals("lucee/runtime/ComponentImpl")) {
                if (loader == null) {
                    throw new RuntimeException("instrumention ComponentImpl but core loader not seen yet");
                }
                return instrumentComponentImpl(classfileBuffer, loader);
            }
            else if (className.equals("lucee/runtime/PageContextImpl")) {
                GlobalIDebugManagerHolder.luceeCoreLoader = loader;

                try {
                    Method m = ClassLoader.class.getDeclaredMethod("defineClass", String.class, byte[].class, int.class, int.class);
                    m.setAccessible(true);

                    for (var injection : pendingCoreLoaderClassInjections) {
                        // warn: reflection ... when does that become unsupported?
                        m.invoke(GlobalIDebugManagerHolder.luceeCoreLoader, injection.name, injection.bytes, 0, injection.bytes.length);
                    }
                    
                    pendingCoreLoaderClassInjections = null;

                    try {
                        final var klass = GlobalIDebugManagerHolder.luceeCoreLoader.loadClass("luceedebug.coreinject.DebugManager");
                        GlobalIDebugManagerHolder.debugManager = (IDebugManager)klass.getConstructor().newInstance();

                        System.out.println("[luceedebug] Loaded " + GlobalIDebugManagerHolder.debugManager + " with ClassLoader '" + GlobalIDebugManagerHolder.debugManager.getClass().getClassLoader() + "'");
                        GlobalIDebugManagerHolder.debugManager.spawnWorker(config, jdwpHost, jdwpPort, debugHost, debugPort);

                        // Register native debugger listener for Lucee7+ native breakpoints
                        registerNativeDebuggerListener(loader);
                    }
                    catch (Throwable e) {
                        e.printStackTrace();
                        System.exit(1);
                    }
                    
                    return classfileBuffer;
                }
                catch (Throwable e) {
                    e.printStackTrace();
                    System.exit(1);
                    return null;
                }
            }
            else if (
                superClass.equals("lucee/runtime/ComponentPageImpl")
                || superClass.equals("lucee/runtime/PageImpl")
                || superClass.equals("lucee/runtime/Page") // seems to be necessary for lucee7
            ) {
                // System.out.println("[luceedebug] Instrumenting " + className);
                if (GlobalIDebugManagerHolder.luceeCoreLoader == null) {
                    System.out.println("Got class " + className + " before receiving PageContextImpl, debugging will fail.");
                    System.exit(1);
                }

                return instrumentCfmOrCfc(classfileBuffer, classReader, className);
            }
            else {
                return classfileBuffer;
            }
        }
        catch (Throwable e) {
            e.printStackTrace();
            System.exit(1);
            return null;
        }
    }

    private byte[] instrumentPageContextImpl(final byte[] classfileBuffer) {
        // Weird problems if we try to compute frames ... tries to lookup PageContextImpl but then it's not yet available in the classloader?
        // Mostly meaning, don't do things in PageContextImpl that change frame sizes
        var classWriter = new ClassWriter(/*ClassWriter.COMPUTE_FRAMES |*/ ClassWriter.COMPUTE_MAXS);

        try {
            var instrumenter = new luceedebug.instrumenter.PageContextImpl(Opcodes.ASM9, classWriter, jdwpHost, jdwpPort, debugHost, debugPort);
            var classReader = new ClassReader(classfileBuffer);

            classReader.accept(instrumenter, ClassReader.EXPAND_FRAMES);

            return classWriter.toByteArray();
        }
        catch (Throwable e) {
            System.err.println("[luceedebug] exception during attempted classfile rewrite");
            System.err.println(e.getMessage());
            e.printStackTrace();
            System.exit(1);
            return null;
        }
    }

    private byte[] instrumentClosureScope(final byte[] classfileBuffer) {
        var classWriter = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS);

        try {
            var instrumenter = new luceedebug.instrumenter.ClosureScope(Opcodes.ASM9, classWriter);
            var classReader = new ClassReader(classfileBuffer);

            classReader.accept(instrumenter, ClassReader.EXPAND_FRAMES);

            return classWriter.toByteArray();
        }
        catch (Throwable e) {
            System.err.println("[luceedebug] exception during attempted classfile rewrite");
            System.err.println(e.getMessage());
            e.printStackTrace();
            System.exit(1);
            return null;
        }
    }

    private byte[] instrumentComponentImpl(final byte[] classfileBuffer, ClassLoader loader) {
        var classWriter = new ClassWriter(/*ClassWriter.COMPUTE_FRAMES |*/ ClassWriter.COMPUTE_MAXS) {
            @Override
            protected ClassLoader getClassLoader() {
                return loader;
            }
        };

        try {
            var instrumenter = new luceedebug.instrumenter.ComponentImpl(Opcodes.ASM9, classWriter);
            var classReader = new ClassReader(classfileBuffer);

            classReader.accept(instrumenter, ClassReader.EXPAND_FRAMES);

            return classWriter.toByteArray();
        }
        catch (Throwable e) {
            System.err.println("[luceedebug] exception during attempted classfile rewrite");
            System.err.println(e.getMessage());
            e.printStackTrace();
            System.exit(1);
            return null;
        }
    }
    
    private byte[] instrumentCfmOrCfc(final byte[] classfileBuffer, ClassReader reader, String className) {
        byte[] stepInstrumentedBuffer = classfileBuffer;
        var classWriter = new ClassWriter(ClassWriter.COMPUTE_FRAMES | ClassWriter.COMPUTE_MAXS) {
            @Override
            protected ClassLoader getClassLoader() {
                return GlobalIDebugManagerHolder.luceeCoreLoader;
            }
        };

        try {
            var instrumenter = new luceedebug.instrumenter.CfmOrCfc(Opcodes.ASM9, classWriter, className);
            var classReader = new ClassReader(stepInstrumentedBuffer);

            classReader.accept(instrumenter, ClassReader.EXPAND_FRAMES);

            return classWriter.toByteArray();
        }
        catch (MethodTooLargeException e) {
            String baseName = e.getMethodName();
            boolean targetMethodWasBeingInstrumented = false;

            if (baseName.startsWith("__luceedebug__")) {
                baseName = baseName.replaceFirst("__luceedebug__", "");
                targetMethodWasBeingInstrumented = true;
            }

            if (targetMethodWasBeingInstrumented) {
                System.err.println("[luceedebug] Method '" + baseName + "' in class '" + className + "' became too large after instrumentation (size="  + e.getCodeSize() + "). luceedebug won't be able to hit breakpoints in, or expose frame information for, this file.");
            }
            else {
                // this shouldn't happen, we really should only get MethodTooLargeExceptions for code we were instrumenting
                System.err.println("[luceedebug] Method " + baseName + " in class " + className + " was too large to for org.objectweb.asm to reemit.");
            }

            return classfileBuffer;
        }
        catch (Throwable e) {
            System.err.println("[luceedebug] exception during attempted classfile rewrite");
            System.err.println(e.getMessage());
            e.printStackTrace();
            System.exit(1);
            return null;
        }
    }

    /**
     * Register our NativeDebuggerListener with Lucee's DebuggerRegistry (if available).
     * This enables native breakpoints in Lucee7+ without JDWP instrumentation.
     *
     * The listener is registered via reflection since DebuggerListener/DebuggerRegistry
     * are in Lucee core, not the loader.
     */
    private void registerNativeDebuggerListener(ClassLoader luceeLoader) {
        try {
            // Check if DebuggerRegistry exists (Lucee7+ feature)
            Class<?> registryClass;
            try {
                registryClass = luceeLoader.loadClass("lucee.runtime.debug.DebuggerRegistry");
            } catch (ClassNotFoundException e) {
                System.out.println("[luceedebug] DebuggerRegistry not found - native breakpoints not available (pre-Lucee7)");
                return;
            }

            // Load the DebuggerListener interface
            Class<?> listenerInterface = luceeLoader.loadClass("lucee.runtime.debug.DebuggerListener");

            // Load our NativeDebuggerListener class (already injected into core loader)
            Class<?> nativeListenerClass = GlobalIDebugManagerHolder.luceeCoreLoader.loadClass("luceedebug.coreinject.NativeDebuggerListener");
            Class<?> pageContextClass = luceeLoader.loadClass("lucee.runtime.PageContext");

            // Cache method lookups - shouldSuspend is on the hot path (called every line)
            final Method onSuspendMethod = nativeListenerClass.getMethod("onSuspend",
                pageContextClass, String.class, int.class, String.class);
            final Method onResumeMethod = nativeListenerClass.getMethod("onResume", pageContextClass);
            final Method shouldSuspendMethod = nativeListenerClass.getMethod("shouldSuspend",
                pageContextClass, String.class, int.class);

            // Create a dynamic proxy that implements DebuggerListener and delegates to our static methods
            Object listenerProxy = java.lang.reflect.Proxy.newProxyInstance(
                luceeLoader,
                new Class<?>[] { listenerInterface },
                (proxy, method, args) -> {
                    String methodName = method.getName();
                    switch (methodName) {
                        case "onSuspend":
                            return onSuspendMethod.invoke(null, args);
                        case "onResume":
                            return onResumeMethod.invoke(null, args);
                        case "shouldSuspend":
                            return shouldSuspendMethod.invoke(null, args);
                        default:
                            throw new UnsupportedOperationException("Unknown method: " + methodName);
                    }
                }
            );

            // Register the listener
            Method setListener = registryClass.getMethod("setListener", listenerInterface);
            setListener.invoke(null, listenerProxy);

            System.out.println("[luceedebug] Registered native debugger listener for Lucee7+ breakpoints");
        } catch (Throwable e) {
            System.out.println("[luceedebug] Failed to register native debugger listener: " + e.getMessage());
            e.printStackTrace();
            // Don't exit - native breakpoints are optional, JDWP breakpoints still work
        }
    }
}
