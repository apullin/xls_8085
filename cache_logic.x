// Cache Logic for SPI Flash ROM Controller
// Implements address decoding, tag comparison, and hit detection
//
// Cache organization (direct-mapped):
//   32 lines × 64 bytes = 2KB
//   Address: [bank:3][addr:15] = 18 bits total
//   Tag:     bank[2:0] ++ addr[14:11] = 12 bits
//   Index:   addr[10:6] = 5 bits (32 lines)
//   Offset:  addr[5:0] = 6 bits (64 bytes per line)

// ============================================================================
// Types
// ============================================================================

// Decoded cache address fields
struct CacheAddr {
    tag: u12,       // Identifies which 64-byte block
    index: u5,      // Selects 1 of 32 cache lines
    offset: u6,     // Byte position within line
}

// Tag entry stored in tag RAM
struct TagEntry {
    valid: u1,      // Line contains valid data
    tag: u12,       // Tag for this line
}

// Result of cache lookup
struct CacheLookup {
    hit: u1,              // 1 = cache hit, 0 = miss
    tag: u12,             // Computed tag (for storing on miss)
    index: u5,            // Cache line index
    offset: u6,           // Byte offset within line
    line_addr: u18,       // Full flash address, line-aligned (for fill)
}

// ============================================================================
// Address Decoding
// ============================================================================

// Decode a ROM address + bank into cache fields
fn decode_address(addr: u15, bank: u3) -> CacheAddr {
    // Tag = bank[2:0] ++ addr[14:11] (12 bits)
    let tag_high = bank as u12;
    let tag_low = (addr >> u15:11) as u12;
    let tag = (tag_high << u12:9) | tag_low;

    // Index = addr[10:6] (5 bits)
    let index = ((addr >> u15:6) & u15:0x1F) as u5;

    // Offset = addr[5:0] (6 bits)
    let offset = (addr & u15:0x3F) as u6;

    CacheAddr { tag, index, offset }
}

// Compute line-aligned flash address for cache fill
fn compute_line_address(addr: u15, bank: u3) -> u18 {
    // Flash address = bank[2:0] ++ addr[14:0], then mask to line boundary
    let full_addr = ((bank as u18) << u18:15) | (addr as u18);
    full_addr & u18:0x3FFC0  // Clear offset bits [5:0]
}

// ============================================================================
// Tag Comparison
// ============================================================================

// Check if stored tag matches expected tag
fn check_hit(stored: TagEntry, expected_tag: u12) -> u1 {
    stored.valid & (stored.tag == expected_tag) as u1
}

// ============================================================================
// Main Lookup Function
// ============================================================================

// Perform complete cache lookup
// Inputs:
//   addr: 15-bit ROM address (0x0000-0x7FFF window)
//   bank: 3-bit bank select (8 banks × 32KB = 256KB)
//   stored_valid: Valid bit from tag RAM for this index
//   stored_tag: Tag from tag RAM for this index
// Outputs:
//   CacheLookup with hit status, decoded fields, and line address for fills
pub fn cache_lookup(
    addr: u15,
    bank: u3,
    stored_valid: u1,
    stored_tag: u12
) -> CacheLookup {
    let decoded = decode_address(addr, bank);
    let stored_entry = TagEntry { valid: stored_valid, tag: stored_tag };
    let hit = check_hit(stored_entry, decoded.tag);
    let line_addr = compute_line_address(addr, bank);

    CacheLookup {
        hit,
        tag: decoded.tag,
        index: decoded.index,
        offset: decoded.offset,
        line_addr,
    }
}

// ============================================================================
// Byte Selection (for use after EBR read)
// ============================================================================

// Select a byte from an 8-byte chunk based on lower offset bits
// (Data RAM is organized as 8-byte wide words for efficiency)
fn select_byte_from_chunk(chunk: u64, offset_low: u3) -> u8 {
    let shift_amount = (offset_low as u6) << u6:3;  // offset * 8
    (chunk >> shift_amount) as u8
}

// ============================================================================
// Tests
// ============================================================================

#[test]
fn test_decode_address_basic() {
    // Address 0x0000, bank 0 -> tag=0, index=0, offset=0
    let result = decode_address(u15:0x0000, u3:0);
    assert_eq(result.tag, u12:0);
    assert_eq(result.index, u5:0);
    assert_eq(result.offset, u6:0);
}

#[test]
fn test_decode_address_offset() {
    // Address 0x003F, bank 0 -> offset should be 63
    let result = decode_address(u15:0x003F, u3:0);
    assert_eq(result.offset, u6:63);
}

#[test]
fn test_decode_address_index() {
    // Address 0x0040 (bit 6 set), bank 0 -> index should be 1
    let result = decode_address(u15:0x0040, u3:0);
    assert_eq(result.index, u5:1);
    assert_eq(result.offset, u6:0);

    // Address 0x07C0 (bits 10:6 = 11111), bank 0 -> index should be 31
    let result2 = decode_address(u15:0x07C0, u3:0);
    assert_eq(result2.index, u5:31);
}

#[test]
fn test_decode_address_tag() {
    // Address 0x0800 (bit 11 set), bank 0 -> tag should have bit 0 set
    let result = decode_address(u15:0x0800, u3:0);
    assert_eq(result.tag, u12:1);

    // Address 0x7800 (bits 14:11 = 1111), bank 0 -> tag should be 0x00F
    let result2 = decode_address(u15:0x7800, u3:0);
    assert_eq(result2.tag, u12:0x00F);
}

#[test]
fn test_decode_address_bank() {
    // Address 0x0000, bank 7 -> tag should have bank in high bits
    let result = decode_address(u15:0x0000, u3:7);
    assert_eq(result.tag, u12:0xE00);  // 7 << 9 = 0xE00

    // Address 0x7800, bank 7 -> tag = 0xE00 | 0x00F = 0xE0F
    let result2 = decode_address(u15:0x7800, u3:7);
    assert_eq(result2.tag, u12:0xE0F);
}

#[test]
fn test_check_hit_valid_match() {
    let entry = TagEntry { valid: u1:1, tag: u12:0x123 };
    assert_eq(check_hit(entry, u12:0x123), u1:1);
}

#[test]
fn test_check_hit_valid_mismatch() {
    let entry = TagEntry { valid: u1:1, tag: u12:0x123 };
    assert_eq(check_hit(entry, u12:0x456), u1:0);
}

#[test]
fn test_check_hit_invalid() {
    let entry = TagEntry { valid: u1:0, tag: u12:0x123 };
    assert_eq(check_hit(entry, u12:0x123), u1:0);  // Invalid = miss even if tag matches
}

#[test]
fn test_compute_line_address() {
    // Address 0x1234, bank 0 -> line address = 0x01200 (clear bits 5:0)
    let result = compute_line_address(u15:0x1234, u3:0);
    assert_eq(result, u18:0x01200);

    // Address 0x1234, bank 3 -> line address = 0x19200
    // bank 3 << 15 = 0x18000, plus 0x1200 = 0x19200
    let result2 = compute_line_address(u15:0x1234, u3:3);
    assert_eq(result2, u18:0x19200);
}

#[test]
fn test_cache_lookup_hit() {
    // Lookup address 0x1234, bank 0
    // Stored tag matches computed tag -> hit
    let decoded = decode_address(u15:0x1234, u3:0);
    let result = cache_lookup(u15:0x1234, u3:0, u1:1, decoded.tag);
    assert_eq(result.hit, u1:1);
    assert_eq(result.offset, u6:0x34);
}

#[test]
fn test_cache_lookup_miss_tag() {
    // Lookup address 0x1234, bank 0
    // Stored tag is different -> miss
    let result = cache_lookup(u15:0x1234, u3:0, u1:1, u12:0xFFF);
    assert_eq(result.hit, u1:0);
}

#[test]
fn test_cache_lookup_miss_invalid() {
    // Lookup address 0x1234, bank 0
    // Tag matches but invalid -> miss
    let decoded = decode_address(u15:0x1234, u3:0);
    let result = cache_lookup(u15:0x1234, u3:0, u1:0, decoded.tag);
    assert_eq(result.hit, u1:0);
}

#[test]
fn test_select_byte() {
    // 8-byte chunk with distinct bytes
    let chunk = u64:0x0706050403020100;
    assert_eq(select_byte_from_chunk(chunk, u3:0), u8:0x00);
    assert_eq(select_byte_from_chunk(chunk, u3:1), u8:0x01);
    assert_eq(select_byte_from_chunk(chunk, u3:7), u8:0x07);
}
