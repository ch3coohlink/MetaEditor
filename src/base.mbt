fn has_prefix(text: String, prefix: String) -> Bool {
  text.length() >= prefix.length() && text[:prefix.length()].to_string() == prefix
}
