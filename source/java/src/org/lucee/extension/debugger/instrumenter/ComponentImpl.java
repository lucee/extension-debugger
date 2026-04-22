package org.lucee.extension.debugger.instrumenter;

import org.objectweb.asm.*;
import org.objectweb.asm.commons.GeneratorAdapter;

public class ComponentImpl extends ClassVisitor {
    public ComponentImpl(int api, ClassWriter cw) {
        super(api, cw);
    }

    @Override
    public void visit(
        int version,
        int access,
        String name,
        String signature,
        String superName,
        String[] interfaces
    ) {
        final var augmentedInterfaces = new String[interfaces.length + 1];
        for (int i = 0; i < interfaces.length; i++) {
            augmentedInterfaces[i] = interfaces[i];
        }
        augmentedInterfaces[interfaces.length] = "org/lucee/extension/debugger/coreinject/ComponentScopeMarkerTraitShim";

        super.visit(version, access, name, signature, superName, augmentedInterfaces);
    }

    @Override
    public void visitEnd() {
        final var fieldName = "__luceedebug__pinned_componentScopeMarkerTrait";
        visitField(Opcodes.ACC_PUBLIC | Opcodes.ACC_TRANSIENT, fieldName, "Ljava/lang/Object;", null, null);

        final var name = "__luceedebug__pinComponentScopeMarkerTrait";
        final var descriptor = "(Ljava/lang/Object;)V";
        final var mv = visitMethod(Opcodes.ACC_PUBLIC, name, descriptor, null, null);
        final var ga = new GeneratorAdapter(mv, Opcodes.ACC_PUBLIC, name, descriptor);

        ga.loadThis();
        ga.loadArg(0);
        ga.putField(Type.getType("Llucee/runtime/ComponentImpl;"), fieldName, Type.getType("Ljava/lang/Object;"));
        ga.visitInsn(Opcodes.RETURN);
        ga.endMethod();
    }
}
