// Module: json
module move_json::json;

use std::string::{String, Self};

use sui::vec_map::{VecMap, Self};


// Is this a zero copy library? how performant

public struct JSONObjectStore has copy, drop, store {
    objects: vector<VecMap<String, JSONValue>>,
    arrays: vector<vector<JSONValue>>
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

public fun borrow_object_data(ref: &ObjectRef, store: &JSONObjectStore): &VecMap<String, JSONValue> {
    &store.objects[ref.object_idx]
}

public fun borrow_array_data(ref: &ArrayRef, store: &JSONObjectStore): &vector<JSONValue> {
    &store.arrays[ref.array_idx]
}

public fun new_object_store(): JSONObjectStore {
    JSONObjectStore {
        objects: vector::empty(),
        arrays: vector::empty()
    }
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

public fun array(p: &mut JSONObjectStore, arr: vector<JSONValue>): JSONValue {
    let array_idx = p.arrays.length();
    let ref = ArrayRef { array_idx };
    p.arrays.push_back(arr);

    JSONValue::Array(ref)
}


public fun object(p: &mut JSONObjectStore, o: VecMap<String, JSONValue>): JSONValue {
    let object_idx = p.objects.length();
    let ref = ObjectRef { object_idx };
    p.objects.push_back(o);
    
    JSONValue::Object(ref)
}

public enum JSONIndex has copy, drop, store {
    Array(u64),
    Object(String)    
}

public fun array_index(idx: u64): JSONIndex {
    JSONIndex::Array(idx)
}

public fun as_array_idx(idx: JSONIndex): u64 {
    match (idx) {
        JSONIndex::Array(n) => n,
        _ => abort EInvalidPath
    }
}

public fun obj_index(key: String): JSONIndex {
    JSONIndex::Object(key)
}

public fun as_object_idx(idx: JSONIndex): String {
    match (idx) {
        JSONIndex::Object(s) => s,
        _ => abort EInvalidPath
    }
}

#[error]
const EInvalidPath: vector<u8> = b"Path was invalid";

public fun get_path(val: &JSONValue, store: &JSONObjectStore, path: &vector<JSONIndex>): JSONValue {
    let mut last_val = *val;
    let mut i = 0;
    while (i < path.length()) {
        let index = path[i];
        match (val) {
            JSONValue::Array(ref) => {
                let data = ref.borrow_array_data(store);
                let idx = index.as_array_idx();
                last_val = data[idx];
            },
            JSONValue::Object(ref) => {
                let data = ref.borrow_object_data(store);
                let key = index.as_object_idx();
                last_val = data[&key];
            },
            _ => abort EInvalidPath
        };
        i = i + 1;
    };
    last_val
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

public fun unwrap_array(v: &JSONValue, parsed: &mut JSONObjectStore): &mut vector<JSONValue> {
    match (v) {
        JSONValue::Array(ref) => &mut parsed.arrays[ref.array_idx],
        _ => abort EIncorrectType
    }
}

public fun unwrap_object(v: &JSONValue, parsed: &mut JSONObjectStore): &mut VecMap<String, JSONValue> {
    match (v) {
        JSONValue::Object(ref) => &mut parsed.objects[ref.object_idx],
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

public fun serialize(val: &JSONValue, store: &JSONObjectStore): String {
    string::utf8(val.serialize_bytes(store))
}

fun serialize_bytes(val: &JSONValue, store: &JSONObjectStore): vector<u8> {
    match (val) {
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
            
            let arr = store.arrays[ref.array_idx];
            let arr_len = arr.length();

            let mut i = 0;
            while (i < arr_len) {
                let s = arr[i].serialize_bytes(store);
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

            let obj = store.objects[ref.object_idx];
            let keys = obj.keys();
            let keys_len = keys.length();
            let mut i = 0;

            while (i < keys_len) {
                let key = keys[i];
                bytes.append(escape_string_into_bytes(&key));
                bytes.push_back(COLON_UTF8);

                let val = obj[&key];
                bytes.append(val.serialize_bytes(store));

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
    let store = new_object_store();
    let s = null().serialize_bytes(&store);
    assert!(s == b"null");
}

#[test]
fun test_serialize_true() {
    let store = new_object_store();
    let s = boolean(true).serialize_bytes(&store);
    assert!(s == b"true");
}

#[test]
fun test_serialize_false() {
    let store = new_object_store();
    let s = boolean(false).serialize_bytes(&store);
    assert!(s == b"false");
}

#[test]
fun test_serialize_zero() {
    let store = new_object_store();
    let s = number(0).serialize_bytes(&store);
    assert!(s == b"0");
}

#[test]
fun test_serialize_num_1() {
    let store = new_object_store();
    let s = number(123041428).serialize_bytes(&store);
    assert!(s == b"123041428");
}

#[test]
fun test_serialize_num_2() {
    let store = new_object_store();
    let s = number(std::u64::max_value!()).serialize_bytes(&store);
    assert!(s == b"18446744073709551615");
}

#[test]
fun test_serialize_string() {
    let store = new_object_store();
    let s = string(string::utf8(b"Hello World")).serialize_bytes(&store);

    assert!(s == b"\"Hello World\"");
}

#[test]
fun test_serialize_string_empty() {
    let store = new_object_store();
    let s = string(string::utf8(b"")).serialize_bytes(&store);

    assert!(s == b"\"\"");
}

#[test]
fun test_serialize_string_escaped_quotes() {
    let store = new_object_store();
    let s = string(string::utf8(b"hello\"a")).serialize_bytes(&store);

    assert!(s == b"\"hello\\\"a\"");
}

#[test]
fun test_serialize_string_escaped_backslash() {
    let store = new_object_store();
    let s = string(string::utf8(b"hello\\fjasj")).serialize_bytes(&store);

    assert!(s == b"\"hello\\\\fjasj\"");
}

#[test]
fun test_serialize_empty_array() {
    let mut store = new_object_store();
    let arr = store.array(vector::empty());
    let s = arr.serialize_bytes(&store);

    assert!(s == b"[]");
}

#[test]
fun test_serialize_singleton_array() {
    let mut store = new_object_store();
    let mut v = vector::empty();
    v.push_back(boolean(true));
    let arr = store.array(v);
    let s = arr.serialize_bytes(&store);

    assert!(s == b"[true]");
}

#[test]
fun test_serialize_nested_array() {
    let mut store = new_object_store();
    let o = store.object(vec_map::empty());

    let mut vec = vector::empty();
    vec.push_back(o);
    let arr = store.array(vec);
    
    let s = arr.serialize_bytes(&store);

    assert!(s == b"[{}]");
}

#[test]
fun test_serialize_nested_array_1() {
    let mut store = new_object_store();
    let mut map = vec_map::empty();
    map.insert(string::utf8(b"hello"), string(string::utf8(b"world")));
    let o = store.object(map);

    let mut vec = vector::empty();
    vec.push_back(o);
    let arr = store.array(vec);
    
    let s = arr.serialize_bytes(&store);

    assert!(s == b"[{\"hello\":\"world\"}]");
}

#[test]
fun test_serialize_multiple_items_array() {
    // Create new object store
    let mut store = new_object_store();
    
    // On that store, create an empty object and array
    let o = store.object(vec_map::empty());
    let a = store.array(vector::empty());

    // Create an array that contains those and some booleans
    let vec = vector[
        o, boolean(true), boolean(false), a
    ];
    let arr = store.array(vec);
    
    // Serialize into string
    let s = arr.serialize(&store);

    assert!(s == string::utf8(b"[{},true,false,[]]"));
}
