/// A store riding in a route, for a pushed page that shares its caller's
/// state (a board's feed, a place's reviews). Equal only to itself.
struct RouteRef<Object: AnyObject>: Hashable {
  let object: Object

  init(_ object: Object) { self.object = object }

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.object === rhs.object }
  func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(object)) }
}
