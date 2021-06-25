.intel_syntax noprefix
.section .text

.global _start
_start:
    cli
    xor rbp, rbp
    call kernel_main

.global load_gdt
load_gdt:
    lgdt [rdi]
    mov ax, si
    ltr ax
    pop rsi
    mov rdi, rsp
    push 0x10
    push rdi
    pushfq
    push 0x08
    push rsi
    iretq

.global load_idt
load_idt:
    lidt [rdi]
    sti
    ret

.global io_apic_enable
io_apic_enable:
    mov ecx, 0x1b // IA32_APIC_BASE_MSR
    rdmsr
    or eax, 0x800 // IA32_APIC_BASE_MSR_ENABLE
    wrmsr
    ret

// .global cpu_init_bsp
  //   push rbp
    // mov rbp, rsp
    // call cpu_get_bsp
    // mov rdi, rax
    // jmp cpu_init_common

// .global cpu_init
    // mov r12, rdi
    // lea rax, [rdi]

.global cpuid_get_LAPIC_id
cpuid_get_LAPIC_id:
    push rbx
    mov eax, 1
    cpuid
    mov eax, ebx
    shr eax, 24
    and eax, 0xff
    pop rbx
    ret

.global cpu_set_gs_fs_base_MSRs
cpu_set_gs_fs_base_MSRs:
    push rbp
    mov rbp, rsp
    mov rax, cr4
    or rax, 0x10000
    mov cr4, rax
    // here we should get have rdi as parameter
    mov ecx, 0xc0000101 // GS_BASE
    mov eax, edi
    shr rdi, 32
    mov edx, edi
    wrmsr
    pop rbp
    ret
