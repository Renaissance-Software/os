const std = @import("std");
const uefi = std.os.uefi;

var con_out: *uefi.protocols.SimpleTextOutputProtocol = undefined;
var boot_services: *uefi.tables.BootServices = undefined;
var runtime_services: *uefi.tables.RuntimeServices = undefined;

fn print(comptime format: []const u8, args: anytype) void
{
    var buffer: [4096]u8 = undefined;
    const formatted_buffer = std.fmt.bufPrint(buffer[0..], format, args) catch unreachable;

    for (formatted_buffer) |c|
    {
        const fake_c = [2]u16 { c, 0 };
        _ = con_out.outputString(@ptrCast(*const [1:0]u16, &fake_c));
    }
    _ = con_out.outputString(&[_:0]u16 {'\r', '\n'});
}

fn panic(comptime format: []const u8, args: anytype, source: std.builtin.SourceLocation) void
{
    print("PANIC at {s}:{}:{}, {s}()", .{source.file, source.line, source.column, source.fn_name});
    print(format, args);
    _ = boot_services.stall(10000 * 5 * 1000 * 1000);
}

fn assert_eq(comptime T: type, a: T, b: T, source: std.builtin.SourceLocation) void
{
    if (a != b)
    {
        panic("{} != {}", .{a, b}, source);
    }
}

fn assert(condition: bool, source: std.builtin.SourceLocation) void
{
    if (!condition)
    {
        panic("Assert failed", .{}, source);
    }
}

fn assert_success(result: uefi.Status, source: std.builtin.SourceLocation) void
{
    if (result != uefi.Status.Success)
    {
        panic("{s} failed: {}", .{source.fn_name, result}, @src());
    }
}

fn load_file(file_protocol: *uefi.protocols.FileProtocol, comptime filename: []const u8) *uefi.protocols.FileProtocol
{
    var proto: *uefi.protocols.FileProtocol = undefined;
    const filename_u16 : [:0]const u16 = comptime blk:
    {
        var n: [:0]const u16 = &[_:0]u16{};
        for (filename) |c|
        {
            n = n ++ [_]u16{c};
        }

        break :blk n;
    };

    assert_success(file_protocol.open(&proto, filename_u16, uefi.protocols.FileProtocol.efi_file_mode_read, 0), @src());

    return proto;
}

const Elf64 = struct
{
    const FileHeader = extern struct
    {
        // e_ident
        magic: u8 = 0x7f,
        elf_id: [3]u8 = "ELF".*,
        bit_count: u8 = @enumToInt(Bits.b64),
        endianness: u8 = @enumToInt(Endianness.little),
        header_version: u8 = 1,
        os_abi: u8 = @enumToInt(ABI.SystemV),
        abi_version: u8 = 0,
        padding: [7]u8 = [_]u8 { 0 } ** 7,
        object_type: u16 = @enumToInt(ObjectFileType.executable), // e_type
        machine : u16 = @enumToInt(Machine.AMD64),
        version: u32 = 1,
        entry: u64,
        program_header_offset: u64 = 0x40,
        section_header_offset: u64,
        flags: u32 = 0,
        header_size: u16 = 0x40,
        program_header_size: u16 = @sizeOf(ProgramHeader),
        program_header_entry_count: u16 = 1,
        section_header_size: u16 = @sizeOf(SectionHeader),
        section_header_entry_count: u16,
        name_section_header_index: u16,

        const Bits = enum(u8)
        {
            b32 = 1,
            b64 = 2,
        };

        const Endianness = enum(u8)
        {
            little = 1,
            big = 2,
        };

        const ABI = enum(u8)
        {
            SystemV = 0,
        };

        const ObjectFileType = enum(u16)
        {
            none = 0,
            relocatable = 1,
            executable = 2,
            dynamic = 3,
            core = 4,
            lo_os = 0xfe00,
            hi_os = 0xfeff,
            lo_proc = 0xff00,
            hi_proc = 0xffff,
        };

        const Machine = enum(u16)
        {
            AMD64 = 0x3e,
        };
    };

    const ProgramHeader = extern struct
    {
        type: u32 = @enumToInt(ProgramHeaderType.load),
        flags: u32 = @enumToInt(Flags.readable) | @enumToInt(Flags.executable),
        offset: u64,
        virtual_address: u64,
        physical_address: u64,
        size_in_file: u64,
        size_in_memory: u64,
        alignment: u64 = 0,

        const ProgramHeaderType = enum(u32)
        {
            @"null" = 0,
            load = 1,
            dynamic = 2,
            interpreter = 3,
            note = 4,
            shlib = 5, // reserved
            program_header = 6,
            tls = 7,
            lo_os = 0x60000000,
            hi_os = 0x6fffffff,
            lo_proc = 0x70000000,
            hi_proc = 0x7fffffff,
        };

        const Flags = enum(u8)
        {
            executable = 1,
            writable = 2,
            readable = 4,
        };
    };

    const SectionHeader = extern struct
    {
        name_offset: u32,
        type: u32,
        flags: u64,
        address: u64,
        offset: u64,
        size: u64,
        // section index
        link: u32,
        info: u32,
        alignment: u64,
        entry_size: u64,

        // type
        const ID = enum(u32)
        {
            @"null" = 0,
            program_data = 1,
            symbol_table = 2,
            string_table = 3,
            relocation_entries_addends = 4,
            symbol_hash_table = 5,
            dynamic_linking_info = 6,
            notes = 7,
            program_space_no_data = 8,
            relocation_entries = 9,
            reserved = 10,
            dynamic_linker_symbol_table = 11,
            array_of_constructors = 14,
            array_of_destructors = 15,
            array_of_pre_constructors = 16,
            section_group = 17,
            extended_section_indices = 18,
            number_of_defined_types = 19,
            start_os_specific = 0x60000000,
        };

        const Flag = enum(u64)
        {
            writable = 0x01,
            alloc = 0x02,
            executable = 0x04,
            mergeable = 0x10,
            contains_null_terminated_strings = 0x20,
            info_link = 0x40,
            link_order = 0x80,
            os_non_conforming = 0x100,
            section_group = 0x200,
            tls = 0x400,
            mask_os = 0x0ff00000,
            mask_processor = 0xf0000000,
            ordered = 0x4000000,
            exclude = 0x8000000,
        };
    };
};

pub fn main() void
{
    boot_services = uefi.system_table.boot_services.?;
    runtime_services = uefi.system_table.runtime_services;
    con_out = uefi.system_table.con_out.?;

    _ = con_out.reset(false);

    print("Hello kernel", .{});

    var handle_list_size: usize = 0;
    var handle_list: [*]uefi.Handle = undefined;

    while (boot_services.locateHandle(.ByProtocol, &uefi.protocols.SimpleFileSystemProtocol.guid, null, &handle_list_size, handle_list) == .BufferTooSmall)
    {
        assert_success(boot_services.allocatePool(uefi.tables.MemoryType.BootServicesData, handle_list_size, @ptrCast(*[*] align(8) u8, &handle_list)), @src());
    }

    assert(handle_list_size > 0, @src());

    print("Handle list count: {}", .{handle_list_size});

    const handle_count = handle_list_size / @sizeOf(uefi.Handle);
    assert_eq(u64, handle_count, 1, @src());

    const handle = handle_list[0];

    var sfs_proto: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;

    assert_success(boot_services.openProtocol(handle, &uefi.protocols.SimpleFileSystemProtocol.guid, @ptrCast(*?*c_void, &sfs_proto), uefi.handle, null, .{ .get_protocol = true }), @src());

    var file_protocol: *uefi.protocols.FileProtocol = undefined;
    assert_success(sfs_proto.?.openVolume(&file_protocol), @src());

    const kernel_file = load_file(file_protocol, "kernel.elf");

    var file_size: u64 = 0;
    assert_success(kernel_file.setPosition(uefi.protocols.FileProtocol.efi_file_position_end_of_file), @src());
    assert_success(kernel_file.getPosition(&file_size), @src());
    print("File size: {} bytes", .{file_size});
    assert_success(kernel_file.setPosition(0), @src());

    var file_content_ptr: [*]align(16) u8 = undefined;
    assert_success(boot_services.allocatePool(.BootServicesData, file_size, &file_content_ptr), @src());
    const file_content = file_content_ptr[0..file_size];
    var elf_file_header = @ptrCast(*Elf64.FileHeader, file_content.ptr);
    print("ELF64 file header:\n{}\n", .{elf_file_header.*});

    print("Everything succeeded\n", .{});

    _ = boot_services.stall(10 * 5 * 1000 * 1000);
}
