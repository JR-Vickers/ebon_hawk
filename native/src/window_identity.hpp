#pragma once
#include <cstddef>

// Exact window IDs take precedence. A fallback is usable only when exactly
// one candidate without a readable ID matches both bounds and title.
enum class EHWindowChoice { none, exact_id, fallback };
inline EHWindowChoice ehWindowChoice(std::size_t exact, std::size_t fallback) {
    if (exact == 1) return EHWindowChoice::exact_id;
    if (exact > 1) return EHWindowChoice::none;
    return fallback == 1 ? EHWindowChoice::fallback : EHWindowChoice::none;
}

// Test identity against all prior candidates, regardless of discovery source.
template <typename Collection, typename Item, typename Equal>
bool ehContainsIdentity(const Collection &items, const Item &item, Equal equal) {
    for (const auto &existing : items) if (equal(existing, item)) return true;
    return false;
}
