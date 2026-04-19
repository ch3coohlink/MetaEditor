using @shared {
  type EventKind, type EventCfg, type Modify,
  type EventData, type NodeQuery, type NodeValue, type DomNs, type StrValue, type JsValue,
  type DomCmd, type ClearHooks, trait HasClrs, type Rng, type Read, type ReadValue,
  bad_json, json_obj, flat_map, onclr, clean, gen_id, new_rng, split_path,
  assert_fail,
}
using @json { from_json, type JsonPath }