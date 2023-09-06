/// @file

#include "noun.h"

//  [a] is RETAINED, [set] is TRANSFERRED
//
static u3_noun
_to_top(u3_noun a, u3_noun cur)
{
  if ( u3_nul == cur ) {
    return u3nc(u3_nul, a);
  }
  else {
    u3_noun n_a, l_a, r_a;
    u3x_trel(a, &n_a, &l_a, &r_a);

    return _to_top(n_a, r_a);
  }
}

u3_noun
u3qdb_top(u3_noun a)
{
  if ( u3_nul == a ) {
    return u3_nul;
  }
  return _to_top(u3_nul, a);
}

u3_noun
u3wdb_top(u3_noun cor)
{
  return u3qdb_top(u3x_at(u3x_con_sam, cor));
}
