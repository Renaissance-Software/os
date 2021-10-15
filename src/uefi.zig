const std = @import("std");
const uefi = std.os.uefi;
const PSF = @import("psf.zig");
const arch = @import("arch/x86_64/intrinsics.zig");
const Paging = @import("arch/x86_64/paging.zig");

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

pub fn panic(message: []const u8, stack_trace: ?*std.builtin.StackTrace) noreturn
{
    print("Panic: {s}\n", .{message});
    while (true) { }
}

fn uefi_panic(comptime format: []const u8, args: anytype, source: std.builtin.SourceLocation) noreturn
{
    var buffer: [8 * 1024]u8 = undefined;
    const formatted_buffer = std.fmt.bufPrint(buffer[0..], "PANIC at {s}:{}:{}, {s}()", .{source.file, source.line, source.column, source.fn_name}) catch unreachable;
    panic(formatted_buffer, null);
}

fn assert_eq(comptime T: type, a: T, b: T, source: std.builtin.SourceLocation) void
{
    if (a != b)
    {
        uefi_panic("{} != {}", .{a, b}, source);
    }
}

fn assert(condition: bool, source: std.builtin.SourceLocation) void
{
    if (!condition)
    {
        uefi_panic("Assert failed", .{}, source);
    }
}

fn assert_success(result: uefi.Status, source: std.builtin.SourceLocation) void
{
    if (result != uefi.Status.Success)
    {
        uefi_panic("{s} failed: {}", .{source.fn_name, result}, source);
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
pub const GraphicsOutputProtocolMode = extern struct {
    max_mode: u32,
    mode: u32,
    info: *GraphicsOutputModeInformation,
    size_of_info: usize,
    frame_buffer_base: u64,
    frame_buffer_size: usize,
};

pub const GraphicsOutputModeInformation = extern struct {
    version: u32 = undefined,
    horizontal_resolution: u32 = undefined,
    vertical_resolution: u32 = undefined,
    pixel_format: GraphicsPixelFormat = undefined,
    pixel_information: PixelBitmask = undefined,
    pixels_per_scan_line: u32 = undefined,
};

pub const GOP = extern struct
{
    base: u64,
    size: u64,
    width: u32,
    height: u32,
    pixels_per_scanline: u32,

    fn initialize() GOP
    {
        var graphics: *uefi.protocols.GraphicsOutputProtocol = undefined;
        assert_success(boot_services.locateProtocol(&uefi.protocols.GraphicsOutputProtocol.guid, null, @ptrCast(*?*c_void, &graphics)), @src());
        const fb_width = graphics.mode.info.horizontal_resolution;
        const fb_height = graphics.mode.info.vertical_resolution;
        const fb_base = graphics.mode.frame_buffer_base;
        const fb_size = graphics.mode.frame_buffer_size;
        const fb_pixels_per_scanline = graphics.mode.info.pixels_per_scan_line;
        const fb = @intToPtr([*]u32, fb_base);

        print("[FRAMEBUFFER] Base: 0x{x}. Size: {}. Width: {}. Height: {}", .{fb_base, fb_size, fb_width, fb_height}); 

        return GOP
        {
            .base = fb_base,
            .size = fb_size,
            .width = fb_width,
            .height = fb_height,
            .pixels_per_scanline = fb_pixels_per_scanline,
        };
    }
};

pub const Memory = extern struct
{
    map: [*]uefi.tables.MemoryDescriptor,
    size: u64,
    descriptor_size: u64,
};

pub const BootData = extern struct
{
    gop: GOP,
    font: PSF.Font,
    memory: Memory,
    rsdp_address: u64,
    kernel_virtual_start: u64,
    kernel_virtual_end: u64,
    kernel_content: u64,
    kernel_size: u64,
};

var uefi_info: BootData = undefined;

pub fn main() noreturn
{
    boot_services = uefi.system_table.boot_services.?;
    runtime_services = uefi.system_table.runtime_services;
    con_out = uefi.system_table.con_out.?;

    _ = con_out.reset(false);

    var handle_list_size: usize = 0;
    var handle_list: [*]uefi.Handle = undefined;

    while (boot_services.locateHandle(.ByProtocol, &uefi.protocols.SimpleFileSystemProtocol.guid, null, &handle_list_size, handle_list) == .BufferTooSmall)
    {
        assert_success(boot_services.allocatePool(.LoaderData, handle_list_size, @ptrCast(*[*] align(8) u8, &handle_list)), @src());
    }

    assert(handle_list_size > 0, @src());

    const handle_count = handle_list_size / @sizeOf(uefi.Handle);
    assert_eq(u64, handle_count, 1, @src());

    const handle = handle_list[0];

    var sfs_proto: ?*uefi.protocols.SimpleFileSystemProtocol = undefined;

    assert_success(boot_services.openProtocol(handle, &uefi.protocols.SimpleFileSystemProtocol.guid, @ptrCast(*?*c_void, &sfs_proto), uefi.handle, null, .{ .get_protocol = true }), @src());

    var file_protocol: *uefi.protocols.FileProtocol = undefined;
    assert_success(sfs_proto.?.openVolume(&file_protocol), @src());

    uefi_info.gop = GOP.initialize();

    var configuration_table = uefi.system_table.configuration_table;
    const acpi2_table_guid = uefi.tables.ConfigurationTable.acpi_20_table_guid;

    const rsdp_address: u64 = blk:
    {
        for (configuration_table[0..uefi.system_table.number_of_table_entries]) |conf_table|
        {
            if (uefi.Guid.eql(conf_table.vendor_guid, acpi2_table_guid))
            {
                const vendor_table = @ptrCast([*]u8, conf_table.vendor_table);
                if (std.mem.eql(u8, "RSD PTR ", vendor_table[0..8]))
                {
                    break :blk @ptrToInt(vendor_table);
                }
            }

        }
        panic("RSDP not found", null);
    };

    uefi_info.rsdp_address = rsdp_address;
    var memory_map_key: usize = undefined;
    var descriptor_version: u32 = 0;

    const font_file = load_file(file_protocol, "zap-light16.psf");
    var font_header: *PSF.Header = undefined;
    assert_success(boot_services.allocatePool(.LoaderData, handle_list_size, @ptrCast(*[*] align(8) u8, &font_header)), @src());
    var psf_header_size: u64 = @sizeOf(PSF.Header);
    assert_success(font_file.read(&psf_header_size, @ptrCast([*]u8, font_header)), @src());
    assert_eq(u8, font_header.magic[0], PSF.magic[0], @src());
    assert_eq(u8, font_header.magic[1], PSF.magic[1], @src());

    var font_buffer_size: u64 = switch (font_header.mode)
    {
        1 => @intCast(u64, font_header.char_size) * 512,
        else => @intCast(u64, font_header.char_size) * 256,
    };

    assert_success(font_file.setPosition(psf_header_size), @src());
    var font_buffer_ptr: [*]u8 = undefined;
    assert_success(boot_services.allocatePool(.LoaderData, font_buffer_size, @ptrCast(*[*] align(8) u8, &font_buffer_ptr)), @src());
    assert_success(font_file.read(&font_buffer_size, font_buffer_ptr), @src());
    uefi_info.font.header = font_header;
    uefi_info.font.buffer.* = PSF.Buffer {
        .ptr = font_buffer_ptr,
        .size = font_buffer_size,
    };

    const kernel_file = load_file(file_protocol, "kernel.elf");

    var file_size: u64 = 0;
    assert_success(kernel_file.setPosition(uefi.protocols.FileProtocol.efi_file_position_end_of_file), @src());
    assert_success(kernel_file.getPosition(&file_size), @src());
    assert_success(kernel_file.setPosition(0), @src());

    var file_content_ptr: [*]align(0x1000) u8 = undefined;
    const page_size = 0x1000;
    assert_success(boot_services.allocatePool(.LoaderData, file_size, @ptrCast(*[*] align(8) u8, &file_content_ptr)), @src());
    assert_success(kernel_file.read(&file_size, file_content_ptr), @src());
    if (file_size < @sizeOf(std.elf.Elf64_Ehdr))
    {
        uefi_panic("File size too small: {}\n", .{file_size}, @src());
    }

    const file_content = file_content_ptr[0..file_size];
    var file_buffer_stream = std.io.fixedBufferStream(file_content);
    var elf_header = std.elf.Header.read(&file_buffer_stream) catch |err| {
        uefi_panic("Failed to read ELF header\n", .{}, @src());
    };
    print("[KERNEL] File size: {} bytes. Entry: 0x{x}", .{file_size, elf_header.entry});


    var it = elf_header.program_header_iterator(&file_buffer_stream);

    var kernel_virtual_base: u64 = 0;
    var kernel_size: u64 = 0;
    var kernel_page_count: u64 = 0;
    var found_got = false;
    while (it.next() catch uefi_panic("Iterating program headers", .{}, @src())) |ph|
    {
        if (ph.p_type == std.elf.PT_LOAD)
        {
            if (kernel_virtual_base == 0)
            {
                kernel_virtual_base = ph.p_vaddr;
            }
            print("PH: {}\n. Offset: 0x{x}\n", .{ph, ph.p_offset});
            const segment_size = ph.p_memsz;
            kernel_size += segment_size;
            var segment_page_count = segment_size / 0x1000;
            if (segment_size % 0x1000 != 0)
            {
                segment_page_count += 1;
            }

            if (!found_got and segment_size == 0x10)
            {
                found_got = true;
                const got_offset = ph.p_offset;
                print("Physical: 0x{x}. Virtual: 0x{x}. Offset: 0x{x}\n", .{ph.p_paddr, ph.p_vaddr, got_offset});
                var got_section_slice = @ptrCast([*] align(1) u64, &file_content[ph.p_offset])[0..(ph.p_filesz / @sizeOf(u64))];
                assert(got_section_slice.len == 2, @src());
                assert(got_section_slice[0] == kernel_virtual_base, @src());
                uefi_info.kernel_virtual_start = got_section_slice[0];
                uefi_info.kernel_virtual_end = got_section_slice[1];
                print("KS: 0x{x}. KE: 0x{x}\n", .{uefi_info.kernel_virtual_start, uefi_info.kernel_virtual_end});
            }

            kernel_page_count += segment_page_count;
        }
    }

    assert(found_got, @src());

    const kernel_size2 = uefi_info.kernel_virtual_end - uefi_info.kernel_virtual_start;
    print("Kernel size: 0x{x}\n", .{kernel_size2});
    assert(kernel_size2 > kernel_size, @src());
    var kernel_page_count_2 = kernel_size2 / page_size;
    if (kernel_size2 % page_size != 0)
    {
        kernel_page_count_2 += 1;
    }
    assert(kernel_page_count_2 == kernel_page_count, @src());

    var kernel_content: [*] align(0x1000) u8 = undefined;
    assert_success(boot_services.allocatePages(.AllocateAnyPages, .LoaderData, kernel_page_count, &kernel_content), @src());
    std.mem.copy(u8, kernel_content[0..kernel_size2], file_content[0..kernel_size2]);
    print("Kernel address: {*}\n", .{kernel_content});
    uefi_info.kernel_content = @ptrToInt(kernel_content);
    uefi_info.kernel_size = kernel_size2;
    assert_success(boot_services.freePool(file_content_ptr), @src());

    print("Getting memory map...\n", .{});
    while (boot_services.getMemoryMap(&uefi_info.memory.size, uefi_info.memory.map, &memory_map_key, &uefi_info.memory.descriptor_size, &descriptor_version) == .BufferTooSmall)
    {
        assert_success(boot_services.allocatePool(.LoaderData, uefi_info.memory.size, @ptrCast(*[*] align(8) u8, &uefi_info.memory.map)), @src());
    }

    assert_success(boot_services.exitBootServices(uefi.handle, memory_map_key), @src());

    Paging.init(&uefi_info);

    const EntryPointType = fn(*BootData) callconv(.SysV) noreturn;
    const entry_point = @intToPtr(EntryPointType, elf_header.entry);

    entry_point(&uefi_info);
}
