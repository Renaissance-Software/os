.intel_syntax noprefix

.section .text
.global _start

.extern foo

_start:
    call foo
    ret
