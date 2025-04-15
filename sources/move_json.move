// Module: json
module move_json::json;

use std::string::{String, Self};

use sui::vec_map::{VecMap, Self};

// For Move coding conventions, see
// https://docs.sui.io/concepts/sui-move-concepts/conventions

// Should we use table or table_vec
// Is this a zero copy library? how performant
// Does && short circuit

public struct ParsedJSON has copy, drop, store {
    objects: vector<VecMap<String, JSONValue>>,
    arrays: vector<vector<JSONValue>>,
    root: JSONValue
}

public enum JSONValue has copy, drop, store {
    Null,
    Boolean(bool),
    Number(u64),
    String(String),
    Array(ArrayRef),
    Object(ObjectRef)
}

public struct ObjectRef has copy, drop, store {
    object_idx: u64
}

public struct ArrayRef has copy, drop, store {
    array_idx: u64,
}

public fun new_parsed(): ParsedJSON {
    ParsedJSON {
        objects: vector::empty(),
        arrays: vector::empty(),
        root: JSONValue::Null,
    }
}

public fun set_root(p: &mut ParsedJSON, v: JSONValue) {
    p.root = v;
}

public fun get_root(p: &ParsedJSON): JSONValue {
    p.root
}


public fun null(): JSONValue {
    JSONValue::Null
}

public fun boolean(b: bool): JSONValue {
    JSONValue::Boolean(b)
}

public fun string(s: String): JSONValue {
    JSONValue::String(s)
}

public fun number(n: u64): JSONValue {
    JSONValue::Number(n)
}

public fun array(p: &mut ParsedJSON, arr: vector<JSONValue>): JSONValue {
    let array_idx = p.arrays.length();
    let ref = ArrayRef { array_idx };
    p.arrays.push_back(arr);

    JSONValue::Array(ref)
}

public fun object(p: &mut ParsedJSON, o: VecMap<String, JSONValue>): JSONValue {
    let object_idx = p.objects.length();
    let ref = ObjectRef { object_idx };
    p.objects.push_back(o);
    
    JSONValue::Object(ref)
}


#[error]
const EIncorrectType: vector<u8> = b"Value unwrapped with a different type than expected";

public fun unwrap_null(v: &JSONValue) {
    match (v) {
        JSONValue::Null => (),
        _ => abort EIncorrectType
    }
}

public fun unwrap_bool(v: &JSONValue): bool {
    match (v) {
        JSONValue::Boolean(b) => *b,
        _ => abort EIncorrectType
    }
}

public fun unwrap_num(v: &JSONValue): u64 {
    match (v) {
        JSONValue::Number(n) => *n,
        _ => abort EIncorrectType
    }
}

public fun unwrap_string(v: &JSONValue): String {
    match (v) {
        JSONValue::String(s) => *s,
        _ => abort EIncorrectType
    }
}

public fun unwrap_array(v: &JSONValue, parsed: &ParsedJSON): vector<JSONValue> {
    match (v) {
        JSONValue::Array(ref) => parsed.arrays[ref.array_idx],
        _ => abort EIncorrectType
    }
}

public fun unwrap_object(v: &JSONValue, parsed: &ParsedJSON): VecMap<String, JSONValue> {
    match (v) {
        JSONValue::Object(ref) => parsed.objects[ref.object_idx],
        _ => abort EIncorrectType
    }
}

const SERIALIZED_NULL: vector<u8> = b"null";
const SERIALIZED_TRUE: vector<u8> = b"true";
const SERIALIZED_FALSE: vector<u8> = b"false";

const QUOTATION_UTF8: u8 = 0x0022;
const     COMMA_UTF8: u8 = 0x002c;
const   DIGIT_0_UTF8: u8 = 0x0030;
const     COLON_UTF8: u8 = 0x003a;
const BACKSLASH_UTF8: u8 = 0x005c;
const  RBRACKET_UTF8: u8 = 0x005d;
const    RCURLY_UTF8: u8 = 0x007d;

fun escape_string_into_bytes(s: &String): vector<u8> {
    let original = s.as_bytes();
    let original_len = original.length();

    let mut escaped = vector::empty<u8>();
    escaped.push_back(QUOTATION_UTF8);

    let mut i = 0;
    while (i < original_len) {
        let char = original[i];
        if (char == BACKSLASH_UTF8 || char == QUOTATION_UTF8) {
            escaped.push_back(BACKSLASH_UTF8);
            escaped.push_back(char);
        } else {
            escaped.push_back(char);
        };

        i = i + 1;                
    };

    escaped.push_back(QUOTATION_UTF8);
    escaped
}

fun serialize_bytes(p: &ParsedJSON, v: &JSONValue): vector<u8> {
    match (v) {
        JSONValue::Null => SERIALIZED_NULL,
        JSONValue::Boolean(b) => 
            if (*b) { SERIALIZED_TRUE } else { SERIALIZED_FALSE },
        JSONValue::Number(n) => {
            if (*n == 0) {
                return b"0"
            };

            let mut left = *n;
            let mut bytes = vector::empty<u8>();
            while (left > 0) {
                let digit = (left % 10) as u8;
                bytes.push_back(digit + DIGIT_0_UTF8);
                left = left / 10;
            };
            bytes.reverse();
            bytes
        },
        JSONValue::String(s) => escape_string_into_bytes(s),
        JSONValue::Array(ref) => {
            let mut bytes = b"[";
            
            let arr = p.arrays[ref.array_idx];
            let arr_len = arr.length();

            let mut i = 0;
            while (i < arr_len) {
                let s = p.serialize_bytes(&arr[i]);
                bytes.append(s);
                if (i + 1 < arr_len) {
                    bytes.push_back(COMMA_UTF8);
                };
                i = i + 1;
            };

            bytes.push_back(RBRACKET_UTF8);
            bytes
        },
        JSONValue::Object(ref) => {
            let mut bytes = b"{";

            let obj = p.objects[ref.object_idx];
            let keys = obj.keys();
            let keys_len = keys.length();
            let mut i = 0;

            while (i < keys_len) {
                let key = keys[i];
                bytes.append(escape_string_into_bytes(&key));
                bytes.push_back(COLON_UTF8);

                let val = obj[&key];
                bytes.append(p.serialize_bytes(&val));

                if (i + 1 < keys_len) {
                    bytes.push_back(COMMA_UTF8);
                };
                i = i + 1;
            };
            
            bytes.push_back(RCURLY_UTF8);
            bytes
        }
        
    }
}

#[test]
fun test_serialize_null() {
    let p = new_parsed();
    let s = p.serialize_bytes(&null());
    assert!(s == b"null");
}

#[test]
fun test_serialize_true() {
    let p = new_parsed();
    let s = p.serialize_bytes(&boolean(true));
    assert!(s == b"true");
}

#[test]
fun test_serialize_false() {
    let p = new_parsed();
    let s = p.serialize_bytes(&boolean(false));
    assert!(s == b"false");
}

#[test]
fun test_serialize_zero() {
    let p = new_parsed();
    let s = p.serialize_bytes(&number(0));
    assert!(s == b"0");
}

#[test]
fun test_serialize_num_1() {
    let p = new_parsed();
    let s = p.serialize_bytes(&number(123041428));
    assert!(s == b"123041428");
}

#[test]
fun test_serialize_num_2() {
    let p = new_parsed();
    let s = p.serialize_bytes(&number(std::u64::max_value!()));
    assert!(s == b"18446744073709551615");
}

#[test]
fun test_serialize_string() {
    let p = new_parsed();
    let s = p.serialize_bytes(&string(string::utf8(b"Hello World")));

    assert!(s == b"\"Hello World\"");
}

#[test]
fun test_serialize_string_empty() {
    let p = new_parsed();
    let s = p.serialize_bytes(&string(string::utf8(b"")));

    assert!(s == b"\"\"");
}

#[test]
fun test_serialize_string_escaped_quotes() {
    let p = new_parsed();
    let s = p.serialize_bytes(&string(string::utf8(b"hello\"a")));

    assert!(s == b"\"hello\\\"a\"");
}

#[test]
fun test_serialize_string_escaped_backslash() {
    let p = new_parsed();
    let s = p.serialize_bytes(&string(string::utf8(b"hello\\fjasj")));

    assert!(s == b"\"hello\\\\fjasj\"");
}

#[test]
fun test_serialize_empty_array() {
    let mut p = new_parsed();
    let arr = p.array(vector::empty());
    let s = p.serialize_bytes(&arr);

    assert!(s == b"[]");
}

#[test]
fun test_serialize_singleton_array() {
    let mut p = new_parsed();
    let mut v = vector::empty();
    v.push_back(boolean(true));
    let arr = p.array(v);
    let s = p.serialize_bytes(&arr);

    assert!(s == b"[true]");
}

#[test]
fun test_serialize_nested_array() {
    let mut p = new_parsed();
    let o = p.object(vec_map::empty());

    let mut vec = vector::empty();
    vec.push_back(o);
    let arr = p.array(vec);
    
    let s = p.serialize_bytes(&arr);

    assert!(s == b"[{}]");
}

#[test]
fun test_serialize_nested_array_1() {
    let mut p = new_parsed();
    let mut map = vec_map::empty();
    map.insert(string::utf8(b"hello"), string(string::utf8(b"world")));
    let o = p.object(map);

    let mut vec = vector::empty();
    vec.push_back(o);
    let arr = p.array(vec);
    
    let s = p.serialize_bytes(&arr);

    assert!(s == b"[{\"hello\":\"world\"}]");
}

#[test]
fun test_serialize_multiple_items_array() {
    let mut p = new_parsed();
    let o = p.object(vec_map::empty());
    let a = p.array(vector::empty());

    let mut vec = vector::empty();
    vec.push_back(o);
    vec.push_back(boolean(true));
    vec.push_back(boolean(false));
    vec.push_back(a);

    let arr = p.array(vec);
    
    let s = p.serialize_bytes(&arr);

    assert!(s == b"[{},true,false,[]]");
}
