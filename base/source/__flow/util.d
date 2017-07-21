module __flow.util;

import std.traits;

/// Returns: full qualified name of type
template fqn(T) {
    enum fqn = fullyQualifiedName!T;
}

/** enables ducktyping casts
 * Examples:
 * class A {}; class B : A {}; auto foo = (new B()).as!A;
 */
T as(T, S)(S sym){return cast(T)sym;}