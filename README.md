# Move JSON
Written by Matthew Jurenka of [Jurenka Software](https://jurenka.software/)

This library facilitates the parsing and serializing of JSON on-chain. Move does not currently support recursive data types, so to handle nested objects and arrays we have to store them in another struct that is re-used per serialization and deserialization. `JSONValue::Array` and `::Object` are simple structs that just store which index the underlying data is within the `JSONObjectStore` instance.

```
public enum JSONValue has copy, drop, store {
    Null,
    Boolean(bool),
    Number(u64),
    String(String),
    Array(ArrayRef),
    Object(ObjectRef)
}

public struct JSONObjectStore has copy, drop, store {
    objects: vector<VecMap<String, JSONValue>>,
    arrays: vector<vector<JSONValue>>
}

public struct ObjectRef has copy, drop, store {
    object_idx: u64
}

public struct ArrayRef has copy, drop, store {
    array_idx: u64,
}
```

### Examples:

#### Deserializing, modifying, and serializing simple JSON object.
Note that `move_json::deserialize` returns both the root `JSONValue` and the `JSONObjectStore` you will need to access values within an array or object. The same store is needed to re serialize the data.

```
let json_string = string::utf8(b"{\"currency\":\"USDC\",\"coins\":[]}");

// Deserialize json string, returning JSONValue and JSONObjectStore
let (val, mut store) = deserialize(&json_string);

// Get vector<JSONValue> that backs the array and add the json value 10
let coins = val.get_path(&store, &vector[json::obj_index(string::utf8(b"coins"))]);
let vec = coins.unwrap_array(&mut store);
vec.push_back(json::number(10));

// Get VecMap<String, JSONValue> that backs the object at the root of the json document
let root_obj = val.get_path(&store, &vector[]);
let root_map = root_obj.unwrap_object(&mut store);

// Insert `key: 3` and remove currency attribute
root_map.insert(string::utf8(b"key"), json::number(3));
root_map.remove(&string::utf8(b"currency"));

let serialized = val.serialize(&store);

assert!(serialized == string::utf8(b"{\"coins\":[10],\"key\":3}"))
```

#### Creating new JSON array and serializing to string.

```
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
```

#### Get Path

```
TODO
```

### Limitations:

- Only handles positive integers that can fit in u64 (MAX: 18446744073709551615)
- Doesn't unescape control characters in strings
- Won't work with emojis because Sui strings only support utf8

### Test Results

```
[ PASS    ] move_json::json::test_serialize_empty_array
[ PASS    ] move_json::deserialize::deserialize_modify_serialize
[ PASS    ] move_json::json::test_serialize_false
[ PASS    ] move_json::deserialize::test_cannot_have_excess
[ PASS    ] move_json::json::test_serialize_multiple_items_array
[ PASS    ] move_json::json::test_serialize_nested_array
[ PASS    ] move_json::deserialize::test_comma_end_of_array
[ PASS    ] move_json::json::test_serialize_nested_array_1
[ PASS    ] move_json::deserialize::test_comma_end_of_object
[ PASS    ] move_json::json::test_serialize_null
[ PASS    ] move_json::deserialize::test_multiple_attrs
[ PASS    ] move_json::json::test_serialize_num_1
[ PASS    ] move_json::json::test_serialize_num_2
[ PASS    ] move_json::deserialize::test_no_rb_w_comma
[ PASS    ] move_json::json::test_serialize_singleton_array
[ PASS    ] move_json::deserialize::test_no_rb_wo_comma
[ PASS    ] move_json::json::test_serialize_string
[ PASS    ] move_json::deserialize::test_parse_nested_null
[ PASS    ] move_json::json::test_serialize_string_empty
[ PASS    ] move_json::deserialize::test_parse_null_fails_on_early_terminate
[ PASS    ] move_json::json::test_serialize_string_escaped_backslash
[ PASS    ] move_json::json::test_serialize_string_escaped_quotes
[ PASS    ] move_json::deserialize::test_parse_null_fails_on_empty
[ PASS    ] move_json::json::test_serialize_true
[ PASS    ] move_json::deserialize::test_parse_null_fails_on_wrong_chars
[ PASS    ] move_json::json::test_serialize_zero
[ PASS    ] move_json::deserialize::test_parse_root_null
Test result: OK. Total tests: 27; passed: 27; failed: 0
```

#### Disclaimer:

This code is unaudited, and we are not responsible for any loss incurred by use by any bugs. This library is in development and the interface is subject to change.