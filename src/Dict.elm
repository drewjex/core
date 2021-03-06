module Dict exposing
  ( Dict
  , empty, singleton, insert, update, remove
  , isEmpty, member, get, size
  , keys, values, toList, fromList
  , map, foldl, foldr, filter, keepIf, dropIf, partition
  , union, intersect, diff, merge
  )

{-| A dictionary mapping unique keys to values. The keys can be any comparable
type. This includes `Int`, `Float`, `Time`, `Char`, `String`, and tuples or
lists of comparable types.

Insert, remove, and query operations all take *O(log n)* time.

# Dictionaries
@docs Dict

# Build
@docs empty, singleton, insert, update, remove

# Query
@docs isEmpty, member, get, size

# Lists
@docs keys, values, toList, fromList

# Transform
@docs map, foldl, foldr, filter, keepIf, dropIf, partition

# Combine
@docs union, intersect, diff, merge

-}


import Basics exposing (..)
import Debug
import Elm.Kernel.Error
import Maybe exposing (..)
import List exposing (..)



-- DICTIONARIES


-- BBlack and NBlack should only be used during the deletion
-- algorithm. Any other occurrence is a bug and should fail an assert.
type NColor
    = Red
    | Black
    | BBlack  -- Double Black, counts as 2 blacks for the invariant
    | NBlack  -- Negative Black, counts as -1 blacks for the invariant


type LeafColor
    = LBlack
    | LBBlack -- Double Black, counts as 2


{-| A dictionary of keys and values. So a `Dict String User` is a dictionary
that lets you look up a `String` (such as user names) and find the associated
`User`.

    import Dict exposing (Dict)

    users : Dict String User
    users =
      Dict.fromList
        [ ("Alice", User "Alice" 28 1.65)
        , ("Bob"  , User "Bob"   19 1.82)
        , ("Chuck", User "Chuck" 33 1.75)
        ]

    type alias User =
      { name : String
      , age : Int
      , height : Float
      }
-}
type Dict k v
    = RBNode_elm_builtin NColor k v (Dict k v) (Dict k v)
    | RBEmpty_elm_builtin LeafColor


{-| Create an empty dictionary. -}
empty : Dict k v
empty =
  RBEmpty_elm_builtin LBlack


maxWithDefault : k -> v -> Dict k v -> (k, v)
maxWithDefault k v r =
  case r of
    RBEmpty_elm_builtin _ ->
      (k, v)

    RBNode_elm_builtin _ kr vr _ rr ->
      maxWithDefault kr vr rr


{-| Get the value associated with a key. If the key is not found, return
`Nothing`. This is useful when you are not sure if a key will be in the
dictionary.

    animals = fromList [ ("Tom", Cat), ("Jerry", Mouse) ]

    get "Tom"   animals == Just Cat
    get "Jerry" animals == Just Mouse
    get "Spike" animals == Nothing

-}
get : comparable -> Dict comparable v -> Maybe v
get targetKey dict =
  case dict of
    RBEmpty_elm_builtin _ ->
      Nothing

    RBNode_elm_builtin _ key value left right ->
      case compare targetKey key of
        LT ->
          get targetKey left

        EQ ->
          Just value

        GT ->
          get targetKey right


{-| Determine if a key is in a dictionary. -}
member : comparable -> Dict comparable v -> Bool
member key dict =
  case get key dict of
    Just _ ->
      True

    Nothing ->
      False


{-| Determine the number of key-value pairs in the dictionary. -}
size : Dict k v -> Int
size dict =
  sizeHelp 0 dict


sizeHelp : Int -> Dict k v -> Int
sizeHelp n dict =
  case dict of
    RBEmpty_elm_builtin _ ->
      n

    RBNode_elm_builtin _ _ _ left right ->
      sizeHelp (sizeHelp (n+1) right) left


{-| Determine if a dictionary is empty.

    isEmpty empty == True
-}
isEmpty : Dict k v -> Bool
isEmpty dict =
  case dict of
    RBEmpty_elm_builtin _ ->
      True

    RBNode_elm_builtin _ _ _ _ _ ->
      False


{- The actual pattern match here is somewhat lax. If it is given invalid input,
it will do the wrong thing. The expected behavior is:

  red node => black node
  black node => same
  bblack node => xxx
  nblack node => xxx

  black leaf => same
  bblack leaf => xxx
-}
ensureBlackRoot : Dict k v -> Dict k v
ensureBlackRoot dict =
  case dict of
    RBNode_elm_builtin Red key value left right ->
      RBNode_elm_builtin Black key value left right

    _ ->
      dict


{-| Insert a key-value pair into a dictionary. Replaces value when there is
a collision. -}
insert : comparable -> v -> Dict comparable v -> Dict comparable v
insert key value dict =
  update key (always (Just value)) dict


{-| Remove a key-value pair from a dictionary. If the key is not found,
no changes are made. -}
remove : comparable -> Dict comparable v -> Dict comparable v
remove key dict =
  update key (always Nothing) dict


type Flag = Insert | Remove | Same


{-| Update the value of a dictionary for a specific key with a given function. -}
update : comparable -> (Maybe v -> Maybe v) -> Dict comparable v -> Dict comparable v
update targetKey alter dictionary =
  let
    up dict =
      case dict of
        -- expecting only black nodes, never double black nodes here
        RBEmpty_elm_builtin _ ->
          case alter Nothing of
            Nothing ->
              (Same, empty)

            Just v ->
              (Insert, RBNode_elm_builtin Red targetKey v empty empty)

        RBNode_elm_builtin color key value left right ->
          case compare targetKey key of
            EQ ->
              case alter (Just value) of
                Nothing ->
                  (Remove, rem color left right)

                Just newValue ->
                  (Same, RBNode_elm_builtin color key newValue left right)

            LT ->
              let (flag, newLeft) = up left in
              case flag of
                Same ->
                  (Same, RBNode_elm_builtin color key value newLeft right)

                Insert ->
                  (Insert, balance color key value newLeft right)

                Remove ->
                  (Remove, bubble color key value newLeft right)

            GT ->
              let (flag, newRight) = up right in
              case flag of
                Same ->
                  (Same, RBNode_elm_builtin color key value left newRight)

                Insert ->
                  (Insert, balance color key value left newRight)

                Remove ->
                  (Remove, bubble color key value left newRight)

    (finalFlag, updatedDict) =
      up dictionary
  in
    case finalFlag of
      Same ->
        updatedDict

      Insert ->
        ensureBlackRoot updatedDict

      Remove ->
        blacken updatedDict


{-| Create a dictionary with one key-value pair. -}
singleton : comparable -> v -> Dict comparable v
singleton key value =
  insert key value empty



-- HELPERS


isBBlack : Dict k v -> Bool
isBBlack dict =
  case dict of
    RBNode_elm_builtin BBlack _ _ _ _ ->
      True

    RBEmpty_elm_builtin LBBlack ->
      True

    _ ->
      False


moreBlack : NColor -> NColor
moreBlack color =
  case color of
    Black ->
      BBlack

    Red ->
      Black

    NBlack ->
      Red

    BBlack ->
      Elm.Kernel.Error.dictBug 0 -- "Can't make a double black node more black!"


lessBlack : NColor -> NColor
lessBlack color =
  case color of
    BBlack ->
      Black

    Black ->
      Red

    Red ->
      NBlack

    NBlack ->
      Elm.Kernel.Error.dictBug 0 -- "Can't make a negative black node less black!"


{- The actual pattern match here is somewhat lax. If it is given invalid input,
it will do the wrong thing. The expected behavior is:

  node => less black node

  bblack leaf => black leaf
  black leaf => xxx
-}
lessBlackTree : Dict k v -> Dict k v
lessBlackTree dict =
  case dict of
    RBNode_elm_builtin c k v l r ->
      RBNode_elm_builtin (lessBlack c) k v l r

    RBEmpty_elm_builtin _ ->
      RBEmpty_elm_builtin LBlack


-- Remove the top node from the tree, may leave behind BBlacks
rem : NColor -> Dict k v -> Dict k v -> Dict k v
rem color left right =
  case (left, right) of
    (RBEmpty_elm_builtin _, RBEmpty_elm_builtin _) ->
      case color of
        Red ->
          RBEmpty_elm_builtin LBlack

        Black ->
          RBEmpty_elm_builtin LBBlack

        _ ->
          Elm.Kernel.Error.dictBug 0 -- "cannot have bblack or nblack nodes at this point"

    (RBEmpty_elm_builtin cl, RBNode_elm_builtin cr k v l r) ->
      case (color, cl, cr) of
        (Black, LBlack, Red) ->
          RBNode_elm_builtin Black k v l r

        _ ->
          Elm.Kernel.Error.dictBug 0 -- "bad remove"

    (RBNode_elm_builtin cl k v l r, RBEmpty_elm_builtin cr) ->
      case (color, cl, cr) of
        (Black, Red, LBlack) ->
          RBNode_elm_builtin Black k v l r

        _ ->
          Elm.Kernel.Error.dictBug 0 -- "bad remove"

    -- l and r are both RBNodes
    (RBNode_elm_builtin cl kl vl ll rl, RBNode_elm_builtin _ _ _ _ _) ->
      let
        (k, v) =
          maxWithDefault kl vl rl

        newLeft =
          removeMax cl kl vl ll rl
      in
        bubble color k v newLeft right


-- Kills a BBlack or moves it upward, may leave behind NBlack
bubble : NColor -> k -> v -> Dict k v -> Dict k v -> Dict k v
bubble color key value left right =
  if isBBlack left || isBBlack right then
    balance (moreBlack color) key value (lessBlackTree left) (lessBlackTree right)

  else
    RBNode_elm_builtin color key value left right


-- Removes rightmost node, may leave root as BBlack
removeMax : NColor -> k -> v -> Dict k v -> Dict k v -> Dict k v
removeMax color key value left right =
  case right of
    RBEmpty_elm_builtin _ ->
      rem color left right

    RBNode_elm_builtin cr kr vr lr rr ->
      bubble color key value left (removeMax cr kr vr lr rr)


-- generalized tree balancing act
balance : NColor -> k -> v -> Dict k v -> Dict k v -> Dict k v
balance color key value left right =
  let
    dict =
      RBNode_elm_builtin color key value left right
  in
    if blackish dict then
      balanceHelp dict

    else
      dict


blackish : Dict k v -> Bool
blackish dict =
  case dict of
    RBNode_elm_builtin color _ _ _ _ ->
      color == Black || color == BBlack

    RBEmpty_elm_builtin _ ->
      True


balanceHelp : Dict k v -> Dict k v
balanceHelp tree =
  case tree of
    -- double red: left, left
    RBNode_elm_builtin col zk zv (RBNode_elm_builtin Red yk yv (RBNode_elm_builtin Red xk xv a b) c) d ->
      balancedTree col xk xv yk yv zk zv a b c d

    -- double red: left, right
    RBNode_elm_builtin col zk zv (RBNode_elm_builtin Red xk xv a (RBNode_elm_builtin Red yk yv b c)) d ->
      balancedTree col xk xv yk yv zk zv a b c d

    -- double red: right, left
    RBNode_elm_builtin col xk xv a (RBNode_elm_builtin Red zk zv (RBNode_elm_builtin Red yk yv b c) d) ->
      balancedTree col xk xv yk yv zk zv a b c d

    -- double red: right, right
    RBNode_elm_builtin col xk xv a (RBNode_elm_builtin Red yk yv b (RBNode_elm_builtin Red zk zv c d)) ->
      balancedTree col xk xv yk yv zk zv a b c d

    -- handle double blacks
    RBNode_elm_builtin BBlack xk xv a (RBNode_elm_builtin NBlack zk zv (RBNode_elm_builtin Black yk yv b c) (RBNode_elm_builtin Black _ _ _ _ as d)) ->
      RBNode_elm_builtin Black yk yv (RBNode_elm_builtin Black xk xv a b) (balance Black zk zv c (redden d))

    RBNode_elm_builtin BBlack zk zv (RBNode_elm_builtin NBlack xk xv (RBNode_elm_builtin Black _ _ _ _ as a) (RBNode_elm_builtin Black yk yv b c)) d ->
      RBNode_elm_builtin Black yk yv (balance Black xk xv (redden a) b) (RBNode_elm_builtin Black zk zv c d)

    _ ->
      tree


balancedTree : NColor -> k -> v -> k -> v -> k -> v -> Dict k v -> Dict k v -> Dict k v -> Dict k v -> Dict k v
balancedTree col xk xv yk yv zk zv a b c d =
  RBNode_elm_builtin
    (lessBlack col)
    yk
    yv
    (RBNode_elm_builtin Black xk xv a b)
    (RBNode_elm_builtin Black zk zv c d)


-- make the top node black
blacken : Dict k v -> Dict k v
blacken t =
  case t of
    RBEmpty_elm_builtin _ ->
      RBEmpty_elm_builtin LBlack

    RBNode_elm_builtin _ k v l r ->
      RBNode_elm_builtin Black k v l r


-- make the top node red
redden : Dict k v -> Dict k v
redden t =
  case t of
    RBEmpty_elm_builtin _ ->
      Elm.Kernel.Error.dictBug 0 -- "can't make a Leaf red"

    RBNode_elm_builtin _ k v l r ->
      RBNode_elm_builtin Red k v l r



-- COMBINE


{-| Combine two dictionaries. If there is a collision, preference is given
to the first dictionary.
-}
union : Dict comparable v -> Dict comparable v -> Dict comparable v
union t1 t2 =
  foldl insert t2 t1


{-| Keep a key-value pair when its key appears in the second dictionary.
Preference is given to values in the first dictionary.
-}
intersect : Dict comparable v -> Dict comparable v -> Dict comparable v
intersect t1 t2 =
  keepIf (\k _ -> member k t2) t1


{-| Keep a key-value pair when its key does not appear in the second dictionary.
-}
diff : Dict comparable a -> Dict comparable b -> Dict comparable a
diff t1 t2 =
  foldl (\k v t -> remove k t) t1 t2


{-| The most general way of combining two dictionaries. You provide three
accumulators for when a given key appears:

  1. Only in the left dictionary.
  2. In both dictionaries.
  3. Only in the right dictionary.

You then traverse all the keys from lowest to highest, building up whatever
you want.
-}
merge
  :  (comparable -> a -> result -> result)
  -> (comparable -> a -> b -> result -> result)
  -> (comparable -> b -> result -> result)
  -> Dict comparable a
  -> Dict comparable b
  -> result
  -> result
merge leftStep bothStep rightStep leftDict rightDict initialResult =
  let
    stepState rKey rValue (list, result) =
      case list of
        [] ->
          (list, rightStep rKey rValue result)

        (lKey, lValue) :: rest ->
          if lKey < rKey then
            stepState rKey rValue (rest, leftStep lKey lValue result)

          else if lKey > rKey then
            (list, rightStep rKey rValue result)

          else
            (rest, bothStep lKey lValue rValue result)

    (leftovers, intermediateResult) =
      foldl stepState (toList leftDict, initialResult) rightDict
  in
    List.foldl (\(k,v) result -> leftStep k v result) intermediateResult leftovers



-- TRANSFORM


{-| Apply a function to all values in a dictionary.
-}
map : (k -> a -> b) -> Dict k a -> Dict k b
map func dict =
  case dict of
    RBEmpty_elm_builtin _ ->
      RBEmpty_elm_builtin LBlack

    RBNode_elm_builtin color key value left right ->
      RBNode_elm_builtin color key (func key value) (map func left) (map func right)


{-| Fold over the key-value pairs in a dictionary from lowest key to highest key.

    import Dict exposing (Dict)

    getAges : Dict String User -> List String
    getAges users =
      Dict.foldl addAge [] users

    addAge : String -> User -> List String -> List String
    addAge _ user ages =
      user.age :: ages

    -- getAges users == [33,19,28]
-}
foldl : (k -> v -> b -> b) -> b -> Dict k v -> b
foldl func acc dict =
  case dict of
    RBEmpty_elm_builtin _ ->
      acc

    RBNode_elm_builtin _ key value left right ->
      foldl func (func key value (foldl func acc left)) right


{-| Fold over the key-value pairs in a dictionary from highest key to lowest key.

    import Dict exposing (Dict)

    getAges : Dict String User -> List String
    getAges users =
      Dict.foldr addAge [] users

    addAge : String -> User -> List String -> List String
    addAge _ user ages =
      user.age :: ages

    -- getAges users == [28,19,33]
-}
foldr : (k -> v -> b -> b) -> b -> Dict k v -> b
foldr func acc t =
  case t of
    RBEmpty_elm_builtin _ ->
      acc

    RBNode_elm_builtin _ key value left right ->
      foldr func (func key value (foldr func acc right)) left


{-| Filter a dictionary.

**Note:** See [`keepIf`](#keepIf) and [`dropIf`](#dropIf) to filter based on a
test like `(\x -> x < 0)` where it just gives a `Bool`.
-}
filter : (comparable -> a -> Maybe b) -> Dict comparable a -> Dict comparable b
filter func dict =
  let
    maybeAdd k x ys =
      case func k x of
        Nothing ->
          ys

        Just y ->
          insert k y ys
  in
  foldl maybeAdd empty dict


{-| Keep only the key-value pairs that pass the given test. -}
keepIf : (comparable -> v -> Bool) -> Dict comparable v -> Dict comparable v
keepIf isGood dict =
  foldl (\k v d -> if isGood k v then insert k v d else d) empty dict


{-| Drop key-value pairs based on the given test. -}
dropIf : (comparable -> v -> Bool) -> Dict comparable v -> Dict comparable v
dropIf isBad dict =
  foldl (\k v d -> if isBad k v then d else insert k v d) empty dict


{-| Partition a dictionary according to some test. The first dictionary
contains all key-value pairs which passed the test, and the second contains
the pairs that did not.
-}
partition : (comparable -> v -> Bool) -> Dict comparable v -> (Dict comparable v, Dict comparable v)
partition isGood dict =
  let
    add key value (t1, t2) =
      if isGood key value then
        (insert key value t1, t2)

      else
        (t1, insert key value t2)
  in
    foldl add (empty, empty) dict



-- LISTS


{-| Get all of the keys in a dictionary, sorted from lowest to highest.

    keys (fromList [(0,"Alice"),(1,"Bob")]) == [0,1]
-}
keys : Dict k v -> List k
keys dict =
  foldr (\key value keyList -> key :: keyList) [] dict


{-| Get all of the values in a dictionary, in the order of their keys.

    values (fromList [(0,"Alice"),(1,"Bob")]) == ["Alice", "Bob"]
-}
values : Dict k v -> List v
values dict =
  foldr (\key value valueList -> value :: valueList) [] dict


{-| Convert a dictionary into an association list of key-value pairs, sorted by keys. -}
toList : Dict k v -> List (k,v)
toList dict =
  foldr (\key value list -> (key,value) :: list) [] dict


{-| Convert an association list into a dictionary. -}
fromList : List (comparable,v) -> Dict comparable v
fromList assocs =
  List.foldl (\(key,value) dict -> insert key value dict) empty assocs
