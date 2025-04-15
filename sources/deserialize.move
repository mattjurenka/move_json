/// Module: deserialize
module move_json::deserialize;

use std::string::{String, Self};
use sui::vec_map::Self;

use move_json::json::{ParsedJSON, JSONValue, Self};

const QUOTATION_UTF8: u8 = 0x0022;
const     COMMA_UTF8: u8 = 0x002c;

const   DIGIT_0_UTF8: u8 = 0x0030;
const   DIGIT_9_UTF8: u8 = 0x0039;

const     COLON_UTF8: u8 = 0x003a;
const  LBRACKET_UTF8: u8 = 0x005b;
const BACKSLASH_UTF8: u8 = 0x005c;
const  RBRACKET_UTF8: u8 = 0x005d;

const   LOWER_A_UTF8: u8 = 0x0061;
const   LOWER_E_UTF8: u8 = 0x0065;
const   LOWER_F_UTF8: u8 = 0x0066;
const   LOWER_L_UTF8: u8 = 0x006c;
const   LOWER_N_UTF8: u8 = 0x006e;
const   LOWER_R_UTF8: u8 = 0x0072;
const   LOWER_S_UTF8: u8 = 0x0073;
const   LOWER_T_UTF8: u8 = 0x0074;
const   LOWER_U_UTF8: u8 = 0x0075;

const    LCURLY_UTF8: u8 = 0x007b;
const    RCURLY_UTF8: u8 = 0x007d;

const EInvalidJSON: u64 = 0;

public fun deserialize(input: &String): ParsedJSON {
    let bytes = input.as_bytes();
    
    let mut parsed = json::new_parsed();

    let (val, end_idx) = parse_value(&mut parsed, bytes, 0);
    parsed.set_root(val);
    
    assert!(end_idx == bytes.length(), EInvalidJSON);
    parsed
}

fun parse_value(parsed: &mut ParsedJSON, bytes: &vector<u8>, start_idx: u64): (JSONValue, u64) {
    assert!(start_idx < bytes.length(), EInvalidJSON);

    let discrim = bytes[start_idx];

    if (discrim == LOWER_N_UTF8) {
        let next_idx = parse_null(bytes, start_idx);
        return (json::null(), next_idx)
    } else if (discrim == LOWER_T_UTF8) { 
        let next_idx = parse_true(bytes, start_idx);
        return (json::boolean(true), next_idx)
    } else if (discrim == LOWER_F_UTF8) {
        let next_idx = parse_false(bytes, start_idx);
        return (json::boolean(false), next_idx)
    } else if (char_is_digit(discrim)) {
        let (val, next_idx) = parse_num(bytes, start_idx);
        return (json::number(val), next_idx)
    } else if (discrim == QUOTATION_UTF8) {
        let (val, next_idx) = parse_string(bytes, start_idx);
        return (json::string(val), next_idx)
    } else if (discrim == LBRACKET_UTF8) {
        return parse_array(parsed, bytes, start_idx)
    } else if (discrim == LCURLY_UTF8) {
        return parse_object(parsed, bytes, start_idx)
    };

    abort EInvalidJSON
}

fun parse_null(bytes: &vector<u8>, start_idx: u64): u64 {
    assert!(start_idx + 3 < bytes.length(), EInvalidJSON);
    assert!(
        bytes[start_idx + 1] == LOWER_U_UTF8 &&
        bytes[start_idx + 2] == LOWER_L_UTF8 &&
        bytes[start_idx + 3] == LOWER_L_UTF8,
        EInvalidJSON
    );
    start_idx + 4
}

fun parse_true(bytes: &vector<u8>, start_idx: u64): u64 {
    assert!(start_idx + 3 < bytes.length(), EInvalidJSON);
    assert!(
        bytes[start_idx + 1] == LOWER_R_UTF8 &&
        bytes[start_idx + 2] == LOWER_U_UTF8 &&
        bytes[start_idx + 3] == LOWER_E_UTF8,
        EInvalidJSON
    );
    start_idx + 4
}

fun parse_false(bytes: &vector<u8>, start_idx: u64): u64 {
    assert!(start_idx + 4 < bytes.length(), EInvalidJSON);
    assert!(
        bytes[start_idx + 1] == LOWER_A_UTF8 &&
        bytes[start_idx + 2] == LOWER_L_UTF8 &&
        bytes[start_idx + 3] == LOWER_S_UTF8 &&
        bytes[start_idx + 4] == LOWER_E_UTF8,
        EInvalidJSON
    );
    start_idx + 5
}

// can only handle integers
fun parse_num(bytes: &vector<u8>, start_idx: u64): (u64, u64) {
    let mut end_idx = start_idx;
    while (end_idx < bytes.length()) {
        if (char_is_digit(bytes[end_idx])) {
            end_idx = end_idx + 1;
        } else {
            break
        }
    };

    let mut value: u64 = 0;
    let mut idx = end_idx - 1;
    while (idx >= start_idx) {
        value = value + (char_to_digit(bytes[idx]) as u64) * 10u64.pow((end_idx - idx - 1) as u8);
        idx = idx - 1;
    };
    
    (value, end_idx)
}

public fun char_is_digit(charcode: u8): bool {
    charcode >= DIGIT_0_UTF8 && charcode <= DIGIT_9_UTF8
}

public fun char_to_digit(charcode: u8): u8 {
    charcode - DIGIT_0_UTF8 
}

// doesn't convert escaped characters into control codes. Will convert \\ into \ and \" into "
public fun parse_string(bytes: &vector<u8>, start_idx: u64): (String, u64) {
    let mut next_idx = start_idx + 1;
    let mut is_escaped = false;

    let mut val = vector::empty<u8>();

    let bytes_len = bytes.length();
    while (true) {
        assert!(next_idx < bytes_len, EInvalidJSON);
        let byte = bytes[next_idx];
        
        if (is_escaped) {
            is_escaped = false;
            val.push_back(byte);
        } else {
            if (byte == BACKSLASH_UTF8) {
                is_escaped = true;
            } else if (byte == QUOTATION_UTF8) {
                return (string::utf8(val), next_idx + 1)
            } else {
                val.push_back(byte);
            }
        };

        next_idx = next_idx + 1;
    };
    abort EInvalidJSON
}

// parse array and put contents into parsed array arena
public fun parse_array(
    parsed: &mut ParsedJSON, bytes: &vector<u8>, start_idx: u64
): (JSONValue, u64) {
    let mut values = vector::empty<JSONValue>();
    
    let bytes_len = bytes.length();
    let mut next_idx = start_idx;
    
    assert!(bytes[next_idx] == LBRACKET_UTF8, EInvalidJSON);
    next_idx = next_idx + 1;

    while (true) {
        assert!(next_idx < bytes_len, EInvalidJSON);
        if (bytes[next_idx] == RBRACKET_UTF8) {
            next_idx = next_idx + 1;
            break
        };

        let (value, new_next_idx) = parse_value(parsed, bytes, next_idx);
        values.push_back(value);
        next_idx = new_next_idx;

        assert!(next_idx < bytes_len, EInvalidJSON);
        if (bytes[next_idx] == COMMA_UTF8) {
            next_idx = next_idx + 1;
        } else if (bytes[next_idx] == RBRACKET_UTF8) {
            next_idx = next_idx + 1;
            break
        } else {
            abort EInvalidJSON
        }
    };

    let ref = parsed.array(values);

    (ref, next_idx)
}

// parse object and put contents into parsed object arena
public fun parse_object(
    parsed: &mut ParsedJSON, bytes: &vector<u8>, start_idx: u64
): (JSONValue, u64) {
    let mut values = vec_map::empty<String, JSONValue>();

    let bytes_len = bytes.length();
    let mut next_idx = start_idx + 1;
    while (true) {
        assert!(next_idx < bytes_len, EInvalidJSON);

        if (bytes[next_idx] == QUOTATION_UTF8) {
            let (str, after_key_idx) = parse_string(bytes, next_idx);
            next_idx = after_key_idx;

            assert!(next_idx < bytes_len, EInvalidJSON);
            if (bytes[next_idx] == COLON_UTF8) {
                let (val, after_value_idx) = parse_value(parsed, bytes, next_idx + 1);
                next_idx = after_value_idx;
                
                values.insert(str, val);
                
                assert!(next_idx < bytes_len, EInvalidJSON);
                if (bytes[next_idx] == COMMA_UTF8) {
                    next_idx = next_idx + 1;
                } else if (bytes[next_idx] == RCURLY_UTF8) {
                    next_idx = next_idx + 1;
                    break
                } else {
                    assert!(false, EInvalidJSON);
                }
            } else {
                assert!(false, EInvalidJSON);
            }
        } else if (bytes[next_idx] == RCURLY_UTF8) {
            next_idx = next_idx + 1;
            break
        } else {
            assert!(false, EInvalidJSON);
        }
    };

    // insert values into arrays arena and return ArrayRef
    let ref = parsed.object(values);

    (ref, next_idx)
}

// TESTS

#[test]
fun test_parse_root_null() {
    let bytes = b"null";
    
    assert!(parse_null(&bytes, 0) == 4, 0);
}

#[test]
fun test_parse_nested_null() {
    let bytes = b"{\"x\":null}";
    
    assert!(parse_null(&bytes, 5) == 9, 0);
}

#[test]
#[expected_failure]
fun test_parse_null_fails_on_empty() {
    let bytes = b"";
    
    parse_null(&bytes, 0);
}

#[test]
#[expected_failure]
fun test_parse_null_fails_on_early_terminate() {
    let bytes = b"{\"x\":nul";
    
    parse_null(&bytes, 5);
}

#[test]
#[expected_failure]
fun test_parse_null_fails_on_wrong_chars() {
    let bytes = b"{\"x\":nul";
    
    parse_null(&bytes, 2);
}

#[test]
fun test_parse_nested() {
    let json_string = string::utf8(b"{\"Hello World\":[null,123,\"Nested \\\"String\",false,[],{}]}");
    
    let parsed = deserialize(&json_string);
    
    let root_obj = &parsed.get_root().unwrap_object(&parsed);
    let array = root_obj[&string::utf8(b"Hello World")].unwrap_array(&parsed);
    
    let empty_arr = array[4].unwrap_array(&parsed);
    assert!(empty_arr.length() == 0);
    let empty_obj = array[5].unwrap_object(&parsed);
    assert!(empty_obj.size() == 0);
}