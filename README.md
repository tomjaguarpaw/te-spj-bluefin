## Desiderata

### Encapsulation

or "make invalid states unrepresentable"

One desirable property of an effect system is "encapsulation", that
is, it is possible to see what effects an operation does _not_ have
(or more precisely, does not make use of in a way that is externally
visible).  For example, an operation of type `StateT s (ExceptT e
Identity)` does not have `IO` effects (but it does have state effects
of type `s` and exception effects of type `e`).  Furthermore, it must
be possible to handle effects, removing them from the range of effects
that are known to be externally visible.  For example

```.hs
initialState :: s

flip evalStateT initialState ::
  StateT s (ExceptT e Identity) r -> ExceptT e Identity r
```

"handles" the state effect by providing it with an initial state
"`initialState`".  The return value has type `ExceptT e Identity r`,
from which we know that no state effects are externally visible.

How does encapsulation work in Bluefin?  The article "[Plucking
constraints in
Bluefin](https://h2.jaguarpaw.co.uk/posts/bluefin-plucking-constraints/)"
is a partial answer, and can be cribbed for the paper.

### Resource safety

Resource safety means that scarce resources are guaranteed to be
released promptly, even in the presence of an exception that traverses
the cleanup code between where it is thrown and where it is caught.
See [Bluefin streams finalize
promptly](https://h2.jaguarpaw.co.uk/posts/bluefin-streams-finalize-promptly/)
for a discussion of resource safety in Bluefin, pipes and conduit.

For be resource safe, Haskell effect systems probably need to be at
least
[`MonadUnliftIO`](https://www.stackage.org/haddock/lts-22.34/unliftio-core-0.2.1.0/Control-Monad-IO-Unlift.html#t:MonadUnliftIO)
(although we ought to justify this claim).

Some useful notes on resource safety to draw on:
<https://tech.fpcomplete.com/haskell/tutorial/exceptions/>

### What do other effect systems provide?

| Effect system | Encapsulation | State | Exceptions | IO | Resource safety | Non-determinism |
|---|---|---|---|---|---|---|
| Bluefin | ✓ | ✓ | ✓ | ✓ | ✓ | ✗ |
| MTL | ✓ | ✓ | ✓ | ✓ | ? | ✓ |
| ST | ✓ | ✓ | ✗ | ✗ | ✗ | ✗ |
| Polysemy | ✓ | ✓ | ✓ | ✓ | ? | ✓ |
| ReaderT IO | ✗ | ✓ | ✓ | ✓ | ✓ | ✗ |
| heftia | ✓ | ✓ | ✓ | ✓ | 1 | 1 |

- 1: heftia can supports bracketing (resource safety) and arbitrary
  delimited continuations, but cannot mix them.  See, for example
  <https://github.com/sayo-hs/heftia/issues/14#issuecomment-2355403132>

- Transformers, MTL, effectful, polysemy, freeer-effects.
   - Quite complicated
   - Can't do `MonadUnliftIO`
   - ST monad

- ST
  - Explicit STRef
  - No IO at all, nor exceptions
  - Encapsulation!

- ReaderT IO
  - No encapsulation
  - RIO library  MonadUnliftIO class

- Bluefin
  - state, exception, IO (the effects of GHC's IO monad)
  - iterators
  - not: non-determinism
  - concurrency? In principle yes. That's an open question.

Somewhere need to discuss delimited continuations.

We want

   1. IO, exceptions, state
   2. `MonadUnliftIO`
   3. Static encapsulation, so you can know what effects a computation has,
   and handle them to remove them.
   4. Lots of effects, incl non-det, backtracking, search.

### Poster child examples

   - `withHandle`: open a file and be sure you have closed it.  Needs
     `MonadUnliftIO`.  Big deal; resource safety.  (`withHandle` in
     [`examples/Examples.hs`](examples/Examples.hs))

   - map with early exit (`find` in [`examples/Examples.hs`](examples/Examples.hs))
   - map with state and perhaps IO or early exit/exceptions (`printCumSum` in [`examples/Examples.hs`](examples/Examples.hs))
   - make a ref, do IO-state-manipulation on that ref; encapsulate it
     all with run (also `printCumSum` in [`examples/Examples.hs`](examples/Examples.hs))

Seek examples from other papers.  Koka papers.  Order of stacking
implies order of handling.  The latter gives semantics.

### Non-determinism/general algebraic effects/delimited continuations

Regarding non-termination and general delimited continuations /
algebraic effects I think we can incorporate them in Bluefin in a
resource safe way by tracking, through another type parameter, whether
a "reset" would chop of a piece of stack containing a "bracket" (the
thing that ensures resource safety).  I don't know how useful in
practice that is.  Maybe it's something to incorporate in the paper
under a "sketch of future work", or similar.

I (Tom) need to write out the types at least, at some point.

## Oderksy talk

Odersky gave a keynote at ICFP '24: [Capabilities for
control](https://youtu.be/F70QZaMoYJQ?t=2052).  Here are some of my
(Tom's) thoughts on it.

* 44:27 Implemented the `allOK` example in
  [`examples/Examples.hs`](examples/Examples.hs)

* 46:07 `awaitAll`/`awaitAll2`: Bluefin doesn't support "futures" yet,
  so we can't implement this one.

* 46:36 `awaitAllResult`: ditto

* 47:54 Flip `Result`/`Future` is supposed to be impossible, but I
  don't understand why.

* 49:20 A misconception:

  > monads don't commute

  Of course not, they don't even compose!

  > Effects (transformers?) don't commute

  Of course not either! It's the order of handlers that is the
  significant thing and obviously "handlers don't commute".  If you
  use them in a different order, they do different things.

  If you install an exception handler, create a state reference, and
  then throw to the exception handler, the state reference will have
  gone out of scope.

  If you create a state reference, then install an exception handler
  and throw to it, the state reference is still in scope.

* 52:22 "passing all these capabilities around as parameters can get
  really tedious" &nbsp; Bluefin says "no"!  Actually, you want to
  pass capabilities around manually.  It leads to much less implicit
  behaviour and much less difficulty in resolving constraints.

* 55:00 A misconception:

  > unlike other types effects are transitive

  No they aren't!  If a function we call requires an exception effect
  we can wrap it in a try block locally.  We don't have to also
  require an exception effect from our caller.  Just like if a
  function we call requires an `Int` we can make an `Int` locally.  We
  don't have to require an int from our caller too.

* 56:30 A nice slogan:

  > Capabilities support Effect Polymorphism, Naturally

* 57:25 Apparently Java _does_ have checked exception polymorphism!  I
  didn't realise this.  It's difficult to use. We should try to find
  out why.

* 58:20 Scala uses single arrow (`->`) for a "pure function".  This is
  in recent versions of Scala under an extension.  There isn't
  enforcement of purity though, because you can run arbitrary Java
  functions under the `->` arrow.

* 59:30 `CanThrow` example (`catThrowF`/`canThrowXs` in
  [`examples/Examples.hs`](examples/Examples.hs))

* 1:00:59 Scoped capabilities.  Yes, Bluefin has this.

* 1:02:00 `withFile` example (`withHandle` in
  [`examples/Examples.hs`](examples/Examples.hs), as well as an
  example showing that Bluefin's use of the type system prevents us
  from using a file handle after it has been closed)

* 1:12:30 Why bad uses of `withFile` are rejected.

## `ST` as a stepping stone

```.hs
runST :: forall a. (forall s. ST s a) -> a

blockST :: forall a s1. (forall s2. ST (s1,s2) a) -> ST s1 a
-- In original paper
```

Needed

```.hs
lift :: ST s a -> ST (s,t) a
```

Very tiresome. The `(:>)` operator does all that lifting for you.

Tom says: I realised subsequently that `ST` (and `ET` from Launchbury
and Sabry) are quite not direct precursors to Bluefin.  The suite of
operations the provide is subtly different.  Therefore I don't know
how easy it will be to motivate Bluefin by saying "let's start with
`ST` and add more stuff".  Maybe there's still a way.

A property that Bluefin has the `ST` doesn't:

If you have a top-level definition (where `r` is a type expression)

```.hs
foo :: forall es. Eff es r
```

then `es` cannot occur free in `r`.  This doesn't hold for `ST`, where
you can have

```.hs
bar :: forall s. ST s (State s Int)
bar = newSTRef 42
```

This means that any top-level Bluefin definition that is unboundedly
polymorphic in `es` is guaranteed to be suitable for passing to
`runPureEff :: (forall es. Eff es r) -> r`.  I'm not sure that this is
a critical property of Bluefin's `Eff`, but it seems quite nice.

## Papers

* [Monadic state: Axiomatization and type
  safety](https://dl.acm.org/doi/pdf/10.1145/258948.258970) &ndash;
  Launchbury and Sabry

  `blockST` and `importVar`

* [Monadic regions](https://www.cs.cornell.edu/people/fluet/research/rgn-monad/SPACE04/space04.pdf) &ndash; Fluet

  linked to the Launchbury/Sabry paper

* [First Class Dynamic Effect
  Handlers](https://users.cs.northwestern.edu/~robby/icfp2018/icfpws18tyde/icfpws18tydemain-p6-p.pdf)
   &ndash; Leijen TyDe 18

* [Lightweight monadic
  regions](https://okmij.org/ftp/Computation/resource-aware-prog/region-io.pdf)
  &ndash; Kiselyov and Snan

## How type variables relate to capabilities

NB: type variables and capabilities are not in 1-1 correspondence; e.g.
`(x: ST s Int, y: ST s Int)`

TRex `forall a rho.  (rho \ x) => { x:Int | rho } -> Int`

NB: `(e :> es)`  is like a uni-directional coercion in System FC, hence
carries no runtime evidence.
