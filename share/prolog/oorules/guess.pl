% Copyright 2017-2020 Carnegie Mellon University.
% ============================================================================================
% Guessing rules.
% ============================================================================================

:- use_module(library(apply), [maplist/2]).
:- use_module(library(lists), [member/2, append/3]).

take(N, List, Prefix) :-
    length(Prefix, N),
    append(Prefix, _, List).

% Because of the way that we're mixing specific guessing rules with more general guessing
% rules, SWI Prolog is complaining about non-contiugous rules, like so:
%   Clauses of Name/Arity are not together in the source-file
% This directive supresses those errors.
:- discontiguous(guessMethod/1).
:- discontiguous(guessConstructor/1).
:- discontiguous(guessClassHasNoBase/1).
:- discontiguous(guessMergeClasses/1).


countGuess :-
    delta_con(guesses, 1).

countGuess :-
    delta_con(guesses, -1),
    fail.

tryBinarySearchInt(_PosPred, _NegPred, []) :-
    logtraceln('tryBinarySearch empty.'),
    fail.

tryBinarySearchInt(PosPred, NegPred, L) :-
    length(L, 1),
    member(X, L),
    logtraceln('tryBinarySearch on ~Q~Q', [PosPred, L]),
    !,
    (call(PosPred, X);
     logtraceln('The guess ~Q(~Q) was inconsistent with a valid solution.', [PosPred, X]),
     logtraceln('Guessing ~Q(~Q) instead.', [NegPred, X]),
     call(NegPred, X)).

tryBinarySearchInt(PosPred, NegPred, List) :-
    logtraceln('~@tryBinarySearch on ~Q: ~Q', [length(List, ListLen), PosPred, ListLen]),
    logtraceln([List]),
    % First try the positive guess on everything. If that fails, we want to retract all the
    % guesses and recurse on a subproblem.
    maplist(PosPred, List);

    % We failed! Recurse on first half of the list
    logtraceln('We failed! tryBinarySearch on ~Q', [List]),
    %(sanityChecks -> true;
    %(logerrorln('sanityChecks failed after retracting guesses; this should never happen'),
    % halt)),
    length(List, ListLen),
    NewListLen is min(16, (ListLen+1)//2),

    take(NewListLen, List, NewList),

    tryBinarySearchInt(PosPred, NegPred, NewList).

tryBinarySearchInt(_PP, _NP, L) :-
    logtrace('tryBinarySearch completely failed on ~Q', [L]),
    logtraceln(' and will now backtrack to fix an upstream problem.'),
    fail.

% This is a wrapper that limits the number of entries to assert at one time
tryBinarySearch(PP, NP, L, N) :-
    length(L, ListLen),
    ListLen >= N,
    take(N, L, Ltrim),
    !,
    tryBinarySearchInt(PP, NP, Ltrim).

tryBinarySearch(PP, NP, L, _N) :-
    tryBinarySearchInt(PP, NP, L).


:- dynamic numGroup/1.
:- assert(numGroup(1)).

trySetGroup(NewN) :-
    numGroup(OldN),
    retract(numGroup(OldN)),
    assert(numGroup(NewN)).

trySetGroup(NewN) :-
    logtraceln('setting numGroup to ~Q failed so setting to 1', [NewN]),
    % We're backtracking!  Crap.
    retract(numGroup(NewN)),
    assert(numGroup(1)),
    fail.

tryBinarySearch(PP, NP, L) :-
    numGroup(NG),
    logtraceln('Old numGroup is ~Q', [NG]),
    !,
    tryBinarySearch(PP, NP, L, NG),
    % We're successful.  Adjust numgroup.  We need to query again to see if NG changed.
    numGroup(NGagain),
    logtraceln('Old numGroup is (again) ~Q', [NGagain]),
    length(L, ListLength),
    NGp is max(NGagain, min(ListLength, NGagain*2)),
    logtraceln('New numGroup is ~Q', [NGp]),
    trySetGroup(NGp).

% Do not guess if either fact is already true, or if doNotGuess(Fact) exists.
doNotGuessHelper(Fact, _) :-
    Fact, !, fail.
doNotGuessHelper(Fact, _) :-
    doNotGuess(Fact), !, fail.
doNotGuessHelper(_, Fact) :-
    Fact, !, fail.
doNotGuessHelper(_, Fact) :-
    doNotGuess(Fact), !, fail.
% Otherwise we're good!
doNotGuessHelper(_, _).

% --------------------------------------------------------------------------------------------
% Try guessing that a virtual function call is correctly interpreted.
% --------------------------------------------------------------------------------------------
guessVirtualFunctionCall(Out) :-
    reportFirstSeen('guessVirtualFunctionCall'),
    minof((Insn, Constructor, OOffset, VFTable, VOffset),
          (likelyVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset),
           not(factNOTConstructor(Constructor)),
           doNotGuessHelper(
                   factVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset),
                   factNOTVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset)))),

    Out = tryOrNOTVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset).

tryOrNOTVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset) :-
    likelyVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset),
    not(factNOTConstructor(Constructor)),
    doNotGuessHelper(factVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset),
                     factNOTVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset)),
    (
        countGuess,
        tryVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset);
        tryNOTVirtualFunctionCall(Insn, Constructor, OOffset, VFTable, VOffset);
        logwarnln('Something is wrong upstream: ~Q.', invalidVirtualFunctionCall(Insn)),
        fail
    ).

tryVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset) :-
    loginfoln('Guessing ~Q.',
              factVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset)),
    try_assert(factVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset)),
    try_assert(guessedVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset)).

tryNOTVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset) :-
    loginfoln('Guessing ~Q.',
              factNOTVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset)),
    try_assert(factNOTVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset)),
    try_assert(guessedNOTVirtualFunctionCall(Insn, Method, OOffset, VFTable, VOffset)).

% --------------------------------------------------------------------------------------------
% Try guessing that a virtual function table is correctly identified.
% --------------------------------------------------------------------------------------------

guessVFTable(Out) :-
    reportFirstSeen('guessVFTable'),
    % See the commentary at possibleVFTable for how this goal constrains our guesses (and
    % ordering).
    osetof(VFTable,
           (possibleVFTable(VFTable),
            doNotGuessHelper(factVFTable(VFTable),
                             factNOTVFTable(VFTable))),
           VFTableSet),
    Out = tryBinarySearch(tryVFTable, tryNOTVFTable, VFTableSet).

tryOrNOTVFTable(VFTable) :-
    tryVFTable(VFTable);
    tryNOTVFTable(VFTable);
    logwarnln('Something is wrong upstream: ~Q.', invalidVFTable(VFTable)),
    fail.

tryVFTable(VFTable) :-
    countGuess,
    loginfoln('Guessing ~Q.', factVFTable(VFTable)),
    try_assert(factVFTable(VFTable)),
    try_assert(guessedVFTable(VFTable)).

tryNOTVFTable(VFTable) :-
    countGuess,
    loginfoln('Guessing ~Q.', factNOTVFTable(VFTable)),
    try_assert(factNOTVFTable(VFTable)),
    try_assert(guessedNOTVFTable(VFTable)).


% --------------------------------------------------------------------------------------------
% Try guessing that a virtual base table is correctly identified.
% --------------------------------------------------------------------------------------------
guessVBTable(Out) :-
    reportFirstSeen('guessVBTable'),
    validVBTableWrite(_Insn, Method, _Offset, VBTable),
    factMethod(Method),
    doNotGuessHelper(factVBTable(VBTable),
                     factNOTVBTable(VBTable)),
    Out = (
        countGuess,
        tryVBTable(VBTable);
        tryNOTVBTable(VBTable);
        logwarnln('Something is wrong upstream: ~Q.', invalidVBTable(VBTable)),
        fail
    ).

tryVBTable(VBTable) :-
    loginfoln('Guessing ~Q.', factVBTable(VBTable)),
    try_assert(factVBTable(VBTable)),
    try_assert(guessedVBTable(VBTable)).

tryNOTVBTable(VBTable) :-
    loginfoln('Guessing ~Q.', factNOTVBTable(VBTable)),
    try_assert(factNOTVBTable(VBTable)),
    try_assert(guessedNOTVBTable(VBTable)).

% --------------------------------------------------------------------------------------------
% Try guessing that a virtual function table entry is valid.
% --------------------------------------------------------------------------------------------

prioritizedVFTableEntry(VFTable, Offset, Entry) :-
    % First establish that the guess meets minimal requirements.
    possibleVFTableEntry(VFTable, Offset, Entry),
    factVFTable(VFTable),
    % Then that it's not already proved or disproved.
    doNotGuessHelper(factVFTableEntry(VFTable, Offset, Entry),
                     factNOTVFTableEntry(VFTable, Offset, Entry)).

% First priority guess, when we already know Entry is an OO method.
guessVFTableEntry1(VFTable, Offset, Entry) :-
    % Choose a prioritized VFTable entry to guess.
    prioritizedVFTableEntry(VFTable, Offset, Entry),

    % Prioritize guesses where we know that the method is actually an OO method first.  This
    % means that we're not really guessing whether this is a valid entry, we're just guessing
    % whether it's a valid entry in _this_ table.  This is a very safe guess.
    (factMethod(Entry); purecall(Entry)),

    % Prioritize guessing the largest likely offset first.  This clause leads to make fewer
    % guesses that that imply all of the smaller offsets.  This turns out to be important from
    % a performance perspective because it reduces the number of times we need to check the
    % entire system against the valid solution constraints.
    not((prioritizedVFTableEntry(VFTable, LargerOffset, _OtherEntry), LargerOffset > Offset)).

% Second priority guess, when we also have to guess that Entry is an OO method.
guessVFTableEntry2(VFTable, Offset, Entry) :-
    % Choose a prioritized VFTable entry to guess.
    prioritizedVFTableEntry(VFTable, Offset, Entry),

    % While using a weaker standard than the previous VFTableEntry guessing rule, this is also
    % reasonably safe, because we're only guessing entries where there's a plausible case that
    % the Entry is at least a function, and also probably a method.  This guess should be
    % eliminated in favor of the previous rule if possible, but in at least one case in the
    % test suite, we still need this rule because the last entry in the VFTable has no other
    % references and so we miss it entirely without this rule.
    possibleMethod(Entry),

    % Prioritize guessing the largest likely offset first.  This clause leads to make fewer
    % guesses that that imply all of the smaller offsets.  This turns out to be important from
    % a performance perspective because it reduces the number of times we need to check the
    % entire system against the valid solution constraints.
    not((prioritizedVFTableEntry(VFTable, LargerOffset, _OtherEntry), LargerOffset > Offset)).

guessVFTableEntry(Out) :-
    reportFirstSeen('guessVFTableEntry'),
    osetof((VFTable, Offset, Entry),
           guessVFTableEntry1(VFTable, Offset, Entry),
           TupleSet),
    Out = tryBinarySearch(tryVFTableEntry, tryNOTVFTableEntry, TupleSet).

guessVFTableEntry(Out) :-
    osetof((VFTable, Offset, Entry),
           guessVFTableEntry2(VFTable, Offset, Entry),
           TupleSet),
    Out = tryBinarySearch(tryVFTableEntry, tryNOTVFTableEntry, TupleSet).

tryVFTableEntry((VFTable, Offset, Entry)) :- tryVFTableEntry(VFTable, Offset, Entry).
tryVFTableEntry(VFTable, Offset, Entry) :-
    countGuess,
    loginfoln('Guessing ~Q.', factVFTableEntry(VFTable, Offset, Entry)),
    try_assert(factVFTableEntry(VFTable, Offset, Entry)),
    try_assert(guessedVFTableEntry(VFTable, Offset, Entry)).

tryNOTVFTableEntry((VFTable, Offset, Entry)) :- tryNOTVFTableEntry(VFTable, Offset, Entry).
tryNOTVFTableEntry(VFTable, Offset, Entry) :-
    countGuess,
    loginfoln('Guessing ~Q.', factNOTVFTableEntry(VFTable, Offset, Entry)),
    try_assert(factNOTVFTableEntry(VFTable, Offset, Entry)),
    try_assert(guessedNOTVFTableEntry(VFTable, Offset, Entry)).

% --------------------------------------------------------------------------------------------
% Try guessing that an embedded object offset zero is really an inheritance relationship.
% ED_PAPER_INTERESTING
% --------------------------------------------------------------------------------------------
guessDerivedClass(DerivedClass, BaseClass, Offset) :-
    reportFirstSeen('guessDerivedClass'),
    factObjectInObject(DerivedClass, BaseClass, Offset),
    % Over time we've had a lot of different theories about whether we intended to limit this
    % guess to offset zero.  This logic says that the offset must either be zero, or have a
    % proven instance of inheritance at a lower address already.  This isn't strictly correct,
    % but it's sufficient to prevent the rule from making guesses in a really bad order (higher
    % offsets before offset zero).  We can tighten it further in the future, if needed.
    (Offset = 0; (factDerivedClass(DerivedClass, _BaseClass2, LowerO), LowerO < Offset)),
    doNotGuessHelper(factDerivedClass(DerivedClass, BaseClass, Offset),
                     factEmbeddedObject(DerivedClass, BaseClass, Offset)).

guessDerivedClass(Out) :-
    osetof((DerivedClass, BaseClass, Offset),
           guessDerivedClass(DerivedClass, BaseClass, Offset),
           TupleSet),
    Out = tryBinarySearch(tryDerivedClass, tryEmbeddedObject, TupleSet).

tryEmbeddedObject((OuterClass, InnerClass, Offset)) :-
    tryEmbeddedObject(OuterClass, InnerClass, Offset).
tryEmbeddedObject(OuterClass, InnerClass, Offset) :-
    countGuess,
    loginfoln('Guessing ~Q.', factEmbeddedObject(OuterClass, InnerClass, Offset)),
    try_assert(factEmbeddedObject(OuterClass, InnerClass, Offset)),
    try_assert(guessedEmbeddedObject(OuterClass, InnerClass, Offset)).

tryDerivedClass((DerivedClass, BaseClass, Offset)) :- tryDerivedClass(DerivedClass, BaseClass, Offset).
tryDerivedClass(DerivedClass, BaseClass, Offset) :-
    countGuess,
    loginfoln('Guessing ~Q.', factDerivedClass(DerivedClass, BaseClass, Offset)),
    try_assert(factDerivedClass(DerivedClass, BaseClass, Offset)),
    try_assert(guessedDerivedClass(DerivedClass, BaseClass, Offset)).

%% guessEmbeddedObject :-
%%     % It's very clear that we don't want to restrict embedded objects to offset zero.  Perhaps
%%     % we'll eventually find that this rule and guessDerivedClass are really the same.
%%     factObjectInObject(DerivedClass, BaseClass, Offset),
%%     not(factDerivedClass(DerivedClass, BaseClass, Offset)),
%%     not(factEmbeddedObject(DerivedClass, BaseClass, Offset)),
%%     (
%%         % Only here we're guessing embedded object first!
%%         tryEmbeddedObject(DerivedClass, BaseClass, Offset);
%%         tryDerivedClass(DerivedClass, BaseClass, Offset);
%%         logwarnln('Something is wrong upstream: ~Q.',
%%                   invalidEmbeddedObject(DerivedClass, BaseClass, Offset)),
%%         fail
%%     ).

% --------------------------------------------------------------------------------------------
% Try guessing that an address is really method.
% --------------------------------------------------------------------------------------------

% This guess was: callingConvention(Method, '__thiscall'), methodMemberAccess(_I, M, O, _S)...
%
% But changing it to require validMethodMemberAccess is complete nonense, because we're now
% _requiring_ that factMethod() be true for the member access to be valid.  The size filter in
% this rule is more restrictive than the one in validMethodMemberAccess, so we're not really
% losing anything by testing the unvalidated member access.
%
% Requiring a validMethodMemberAccess is essentialy requiring that something in the object be
% accessed in the method.  The justification for using 100 as the limit for the offset size
% here is a bit complicated, but basically the thinking is that medium sized accesses are
% usually accompanied by at least one small access, and we can exclude a few more false
% positives by reducing the limit further beyond what would obviously be too limiting for
% validMethodMemberAccess.
guessMethodA(Method) :-
    callingConvention(Method, '__thiscall'),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    % Intentionally use the _unvalidated_ access to guess that the Method is actually object
    % oriented.  This will be a problem as we export more facts where we don't have the correct
    % calling convention data (e.g. Linux executables)
    methodMemberAccess(_Insn, Method, Offset, _Size),
    Offset < 100.

guessMethod(Out) :-
    reportFirstSeen('guessMethod'),
    osetof(Method,
           guessMethodA(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_A(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

guessMethodB(Method) :-
    factMethod(Caller),
    % It is sufficient for __thiscall to be possible, since our confidence derives from Caller.
    % This rule currently needs to permit the slightly different ECX parameter standard.
    % This bug is wrapped up in std::_Yarn and std::locale in Lite/ooex7 (and oo and poly).
    (callingConvention(Caller, '__thiscall'); callingConvention(Caller, 'invalid')),
    funcParameter(Caller, 'ecx', ThisPtr1),
    thisPtrOffset(ThisPtr1, _Offset, ThisPtr2),
    thisPtrUsage(_Insn1, Caller, ThisPtr2, Method),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)).

% Guess that calls passed offsets into existing objects are methods.  This rule is not
% literally true, but objects are commonly in other objects.
guessMethod(Out) :-
    osetof(Method,
           guessMethodB(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_B(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

% This guess is required (at least for our test suite) in cases where there's no certainty in
% the calling convention, and effectively no facts that would allow us to reach the conclusion
% logically.
% ED_PAPER_INTERESTING
guessMethodC(Method) :-
    callingConvention(Method, '__thiscall'),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    % Also intentionally an unvalidated methodMemberAccess because we're guessing the
    % factMethod() that is required for the validMethodMemberAccess.
    methodMemberAccess(_Insn1, Method, Offset, _Size1),
    Offset < 100,
    validFuncOffset(_Insn2, Caller, Method, _Size2),
    factMethod(Caller).

guessMethod(Out) :-
    osetof(Method,
           guessMethodC(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_C(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

% More kludgy guessing rules. :-( This one is based on thre premise that a cluster of three or
% more nearly OO methods is not a conincidence. A better fix would be for at least one of the
% methods to be detected unambiguously as __thiscall, or to find dataflow from an already true
% method.
:- table guessMethodD/1 as incremental.
guessMethodD(Method) :-
    callingConvention(Method, '__thiscall'),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    validMethodMemberAccess(_Insn0, Method, Offset, _Size0),
    Offset < 100,
    validFuncOffset(_Insn1, Caller1, Method, _Size1),
    validFuncOffset(_Insn2, Caller2, Method, _Size2),
    iso_dif(Caller1, Caller2),
    validFuncOffset(_Insn3, Caller3, Method, _Size3),
    iso_dif(Caller1, Caller3).

guessMethod(Out) :-
    osetof(Method,
           guessMethodD(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_D(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

% A variation of the previous rule using thisPtrUsage and passing around a this-pointer to
% multiple methods.  Just guess the first and the rest will follow...
:- table guessMethodE/1 as incremental.
guessMethodE(Method) :-
    callingConvention(Method, '__thiscall'),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    validMethodMemberAccess(_Insn0, Method, Offset, _Size0),
    Offset < 100,
    thisPtrUsage(_Insn1, Caller, ThisPtr, Method),
    thisPtrUsage(_Insn2, Caller, ThisPtr, Method2),
    iso_dif(Method, Method2),
    thisPtrUsage(_Insn3, Caller, ThisPtr, Method3),
    iso_dif(Method, Method3).


guessMethod(Out) :-
    osetof(Method,
           guessMethodE(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_E(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

% Another case where we're trying to implement the reasoning that there's a lot of stuff
% suggesting that it's a method.  In this case, it's a possible constructor with memory
% accesses.
guessMethodF(Method) :-
    callingConvention(Method, '__thiscall'),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    validMethodMemberAccess(_Insn1, Method, Offset, _Size1),
    Offset < 100,
    (possibleConstructor(Method); possibleDestructor(Method)).

guessMethod(Out) :-
    osetof(Method,
           guessMethodF(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_F(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

% Also guess possible constructors and destructors with calls from known methods.
guessMethodG(Method) :-
    callingConvention(Method, '__thiscall'),
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    thisPtrUsage(_Insn, Caller, _ThisPtr2, Method),
    factMethod(Caller),
    (possibleConstructor(Method); possibleDestructor(Method)).

guessMethod(Out) :-
    osetof(Method,
           guessMethodG(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factMethod_G(MethodSet)),
    Out = tryBinarySearch(tryMethod, tryNOTMethod, MethodSet).

tryMethodNOTMethod(Method):-
    doNotGuessHelper(factMethod(Method),
                     factNOTMethod(Method)),
    (
        tryMethod(Method);
        tryNOTMethod(Method);
        logwarnln('Something is wrong upstream: ~Q.', invalidMethod(Method)),
        fail
    ).

tryMethod(Method) :-
    countGuess,
    loginfoln('Guessing ~Q.', factMethod(Method)),
    try_assert(factMethod(Method)),
    try_assert(guessedMethod(Method)),
    make(Method).

tryNOTMethod(Method) :-
    countGuess,
    loginfoln('Guessing ~Q.', factNOTMethod(Method)),
    try_assert(factNOTMethod(Method)),
    try_assert(guessedNOTMethod(Method)).

% --------------------------------------------------------------------------------------------
% Try guessing that method is a constructor.
% --------------------------------------------------------------------------------------------

% Prefer guessing methods that have confirmed vftable writes first?  It's not clear that this
% was needed, but it doesn't seem harmful provided that we backtrack correctly (and not
% repeatedly, which is why I added the cut).

% We have three approximate indicators of constructor-ness:
%
% 1. The method appears in a _possible_ VFTable, which is strongly negative because we can't
%    presently propose any legitimate reason why that should happen if the method was truly a
%    constructor.
%
% 2. The method has VFTable writes which proves that it's either a constructor or destructor,
%    making our guess much better (at least 50/50) and probably even better if the next
%    indicator is also true.
%
% 3. The method has reads of members that it did not initialize.  This is not allowed for
%    constructors unless the method called the parent constructor which initialized the member.
%    While not impossible this situation is less likely (and probably eliminates many
%    destructors).  Guessing NOTConstructor based on uninitialized reads doesn't work because
%    we have test cases that initialize dervied members from base members.
%
% We're going to prioritize them in roughly that order...  There's still some debate about the
% optimal order of the latter two incicators based on various arguments which cases are more
% common and so forth...

% Perfect virtual case, not in a vftable, writes a vftable, and has no uninitalized reads.
% ED_PAPER_INTERESTING
guessConstructor1(Method) :-
    factMethod(Method),
    possibleConstructor(Method),
    not(possiblyVirtual(Method)),
    factVFTableWrite(_Insn, Method, _ObjectOffset, _VFTable2),
    not(uninitializedReads(Method)),
    doNotGuessHelper(factConstructor(Method),
                     factNOTConstructor(Method)).

guessConstructor(Out) :-
    reportFirstSeen('guessConstructor'),
    osetof(Method,
           guessConstructor1(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factConstructor1(MethodSet)),
    Out = tryBinarySearch(tryConstructor, tryNOTConstructor, MethodSet).

% Likely virtual case, not in a vftable, writes a vftable, but has unitialized reads.
guessConstructor2(Method) :-
    factMethod(Method),
    possibleConstructor(Method),
    not(possiblyVirtual(Method)),
    factVFTableWrite(_Insn, Method, _ObjectOffset, _VFTable2),
    % We don't whether their were unitialized reads or not.  Presumably we called our parent
    % constructor (which kind of makes sense giving that we've already got virtual methods).
    doNotGuessHelper(factConstructor(Method),
                     factNOTConstructor(Method)).

guessConstructor(Out) :-
    osetof(Method,
           guessConstructor2(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factConstructor2(MethodSet)),
    Out = tryBinarySearch(tryConstructor, tryNOTConstructor, MethodSet).

% Normal non-virtual case, not in a vftable, doesn't write a vftable, and has no uninitialized
% reads.
% ED_PAPER_INTERESTING
guessConstructor3(Method) :-
    factMethod(Method),
    possibleConstructor(Method),
    not(possiblyVirtual(Method)),
    % This case is for constructors of non-virtual classes.
    not(uninitializedReads(Method)),
    doNotGuessHelper(factConstructor(Method),
                     factNOTConstructor(Method)).

guessConstructor(Out) :-
    osetof(Method,
           guessConstructor3(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factConstructor3(MethodSet)),
    Out = tryBinarySearch(tryConstructor, tryNOTConstructor, MethodSet).

% Unusual non-virtual case presumably with inheritance -- not in a vftable, doesn't write a
% vftable, but has uninitialized reads.  It's very likely that this class has a base, but we
% don't capture that implication well right now.
guessConstructor4(Method) :-
    factMethod(Method),
    possibleConstructor(Method),
    not(possiblyVirtual(Method)),
    % This case is for constructors of non-virtual classes with uninitalized reads.
    doNotGuessHelper(factConstructor(Method),
                     factNOTConstructor(Method)).

guessUnlikelyConstructor(Out) :-
    reportFirstSeen('guessUnlikelyConstructor'),
    osetof(Method,
           guessConstructor4(Method),
           MethodSet),
    logtraceln('Proposing ~Q.', factConstructor4(MethodSet)),
    Out = tryBinarySearch(tryConstructor, tryNOTConstructor, MethodSet).

tryConstructorNOTConstructor(Method) :-
    doNotGuessHelper(factConstructor(Method),
                     factNOTConstructor(Method)),
    (
        tryConstructor(Method);
        tryNOTConstructor(Method);
        logwarnln('Something is wrong upstream: ~Q.', invalidConstructor(Method)),
        fail
    ).

tryConstructor(Method) :-
    countGuess,
    loginfoln('Guessing ~Q.', factConstructor(Method)),
    try_assert(factConstructor(Method)),
    try_assert(guessedConstructor(Method)).

tryNOTConstructor(Method) :-
    countGuess,
    loginfoln('Guessing ~Q.', factNOTConstructor(Method)),
    try_assert(factNOTConstructor(Method)),
    try_assert(guessedNOTConstructor(Method)).

% --------------------------------------------------------------------------------------------
% Try guessing that constructor has no base class.
% --------------------------------------------------------------------------------------------

% First guess constructors with a single VFTable write...  Because constructors with multiple
% vftable writes are more likely to have base classes.
% ED_PAPER_INTERESTING
guessClassHasNoBaseB(Class) :-
    factConstructor(Constructor),
    find(Constructor, Class),

    factVFTableWrite(_Insn1, Constructor, 0, VFTable),
    not((
               factVFTableWrite(_Insn2, Constructor, _Offset1, OtherVFTable),
               iso_dif(VFTable, OtherVFTable)
       )),

    not(factDerivedClass(Class, _BaseClass, _Offset2)),
    doNotGuessHelper(factClassHasNoBase(Class),
                     factClassHasUnknownBase(Class)).

guessClassHasNoBase(Out) :-
    reportFirstSeen('guessClassHasNoBase'),
    osetof(Class,
           guessClassHasNoBaseB(Class),
           ClassSet),
    logtraceln('Proposing ~P.', 'ClassHasNoBase_B'(ClassSet)),
    Out = tryBinarySearch(tryClassHasNoBase, tryClassHasUnknownBase, ClassSet).

% Then guess classes regardless of their VFTable writes.
% ED_PAPER_INTERESTING
guessClassHasNoBaseC(Class) :-
    factConstructor(Constructor),
    find(Constructor, Class),
    not(factDerivedClass(Class, _BaseClass, _Offset)),
    doNotGuessHelper(factClassHasNoBase(Class),
                     factClassHasUnknownBase(Class)).

guessClassHasNoBase(Out) :-
    osetof(Class,
           guessClassHasNoBaseC(Class),
           ClassSet),
    logtraceln('Proposing ~P.', 'ClassHasNoBase_C'(ClassSet)),
    Out = tryBinarySearch(tryClassHasNoBase, tryClassHasUnknownBase, ClassSet).

tryClassHasNoBase(Class) :-
    countGuess,
    loginfoln('Guessing ~Q.', factClassHasNoBase(Class)),
    try_assert(factClassHasNoBase(Class)),
    try_assert(guessedClassHasNoBase(Class)).

tryClassHasUnknownBase(Class) :-
    countGuess,
    loginfoln('Guessing ~Q.', factClassHasUnknownBase(Class)),
    try_assert(factClassHasUnknownBase(Class)),
    try_assert(guessedClassHasUnknownBase(Class)).


% This is also used to guess factClassHasNoBase, but is one of the last guesses made in the
% system.  The idea is simply to guess factClassHasNoBase for any class that does not have an
% identified base.
guessClassHasNoBaseSpecial(Class) :-
    % Class is a class
    find(_, Class),

    % Class does not have any base classes
    not(factDerivedClass(Class, _Base, _Offset)),

    % XXX: If we're at the end of reasoning and there is an unknown base, is that OK?  Should
    % we leave it as is?  Try really hard to make a guess?  Or treat it as a failure?
    doNotGuessHelper(factClassHasNoBase(Class),
                     factClassHasUnknownBase(Class)).

guessCommitClassHasNoBase(Out) :-
    reportFirstSeen('guessCommitClassHasNoBase'),
    osetof(Class,
           guessClassHasNoBaseSpecial(Class),
           ClassSet),
    logtraceln('Proposing ~P.', 'CommitClassHasNoBase'(ClassSet)),
    Out = tryBinarySearch(tryClassHasNoBase, tryClassHasUnknownBase, ClassSet).


% --------------------------------------------------------------------------------------------
% Various rules for guessing method to class assignments...
% --------------------------------------------------------------------------------------------

% There's a very common paradigm where one constructor calls another constructor, and this
% represents either an embedded object or an inheritance relationship (aka ObjectInObject).
% This rule is strong enough that for a long time it was a forward reasoning rule, until Cory
% realized that technically the required condition was factNOTMergeClasses() instead of just
% currently being on different classes.  Because we needed to make this guess, the weaker logic
% was moved here.
% Ed: This is a guess because Constructor1 could be calling Constructor2 on the same class.
% ED_PAPER_INTERESTING
guessNOTMergeClasses(OuterClass, InnerClass) :-
    reportFirstSeen('guessNOTMergeClasses'),
    % We are certain that this member offset is passed to InnerConstructor.
    validFuncOffset(_CallInsn, OuterConstructor, InnerConstructor, _Offset),
    factConstructor(OuterConstructor),
    factConstructor(InnerConstructor),
    iso_dif(InnerConstructor, OuterConstructor),
    % They're not currently on the same class...
    find(InnerConstructor, InnerClass),
    find(OuterConstructor, OuterClass),
    iso_dif(OuterClass, InnerClass),

    not(uninitializedReads(InnerConstructor)),

    % We've not already concluded that they're different classes.
    doNotGuessHelper(factNOTMergeClasses(OuterClass, InnerClass),
                     factNOTMergeClasses(InnerClass, OuterClass)).


% The symmetry on guessNOTMergeClasses above was a little tricky, and a correction was required
% to pass tests, resulting in this possibly suboptimal approach?
guessNOTMergeClassesSymmetric(Class1, Class2) :-
    guessNOTMergeClasses(A, B),
    sort_tuple((A, B), (Class1, Class2)),
    % Debugging.
    %logtraceln('~Q.', guessNOTMergeClasses(Class1, Class2)),
    true.

guessNOTMergeClasses(Out) :-
    osetof((OuterClass, InnerClass),
           guessNOTMergeClassesSymmetric(OuterClass, InnerClass),
           ClassPairSets),
    Out = tryBinarySearch(tryNOTMergeClasses, tryMergeClasses, ClassPairSets).

% This is one of the strongest of several rules for guessing arbitrary method assignments.  We
% know that the method is very likely to be assigned to one of the two constructors, so we
% should guess both right now.  We don't technically know that it's assign to one or the other,
% because a method might be conflicted between multiple classes.  Perhaps a lot of conflicted
% methods with the same constructors should suggest a class merger between the constructors
% instead (for performance reasons)?
% Ed: Why does it matter that there are two constructors?
guessMergeClassesA(Class1, MethodClass) :-
    factMethod(Method),
    not(purecall(Method)), % Never merge purecall methods into classes.
    validFuncOffset(_Insn1, Constructor1, Method, 0),
    validFuncOffset(_Insn2, Constructor2, Method, 0),
    iso_dif(Constructor1, Constructor2),
    factConstructor(Constructor1),
    factConstructor(Constructor2),
    find(Constructor1, Class1),
    find(Constructor2, Class2),
    find(Method, MethodClass),
    iso_dif(Class1, Class2),
    iso_dif(Class1, Method),
    % This rule is symmetric because Prolog will try binding the same method to Constructor2 on
    % one evluation, and Constructor1 on the next evaluation, so even though the rule is also
    % true for Constructor2, that case will be handled when it's bound to Constructor.
    logtraceln('Proposing ~Q.', factMergeClasses_A(Class1, Method)),
    checkMergeClasses(Class1, MethodClass).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesA'),
    minof((Class, Method),
          guessMergeClassesA(Class, Method)),
    !,
    OneTuple=[(Class, Method)],
    logtraceln('Proposing ~Q.', factMergeClasses_A(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).

% Another good guessing heuristic is that if a virtual call was resolved through a specific
% VFTable, and there's nothing contradictory, try assigning the call to the class that it was
% resolved through.  Technically, I think this is a case of choosing arbitrarily between
% multiple valid solutions.  It might be possible to prove which constructor the method is on.

% This fact was a sub-computation of guessMergeClassesB that added a lot of overhead.  By
% putting it in a separate fact, we can make it a trigger-based fact that is maintained with
% low overhead.
% factMethodInVFTable/3

% trigger
% XXX: Should this be in rules.pl?
%:- table reasonMethodInVFTable/4 as incremental.
reasonMethodInVFTable(VFTable, Offset, Method, Entry) :-
    not(purecall(Entry)),
    factVFTableEntry(VFTable, Offset, Entry),
    dethunk(Entry, Method).

guessMergeClassesB(Class1, Class2) :-
    factVFTableEntry(VFTable, _VFTableOffset, Entry1),
    not(purecall(Entry1)), % Never merge purecall methods into classes.
    dethunk(Entry1, Method1),
    factMethod(Method1),
    not(purecall(Method1)), % Never merge purecall methods into classes.

    % A further complication arose in this guessing heuristic.  It appears that if the method
    % in question is actually an import than this rule is not always true.  For example, in
    % 2010/Debug/ooex7, 0x41138e thunks to 0x414442 which thunks to 0x41d42c which is the
    % import for std::exception::what().  Blocking this guess prevents us from assigning it to
    % the wrong class, but it would be better to just assign it to the right class with a
    % strong reasoning rule.  We don't have one of those for this case yet because we don't
    % have the vftable for the method that's imported...
    not(symbolProperty(Method1, virtual)),

    % Which class is VFTable associated with?
    reasonVFTableBelongsToClass(VFTable, _ObjOffset1, Class2),

    % The method is allowed to appear in other VFTables, but only if they are on the same
    % class.  Ed conjectures this is necessary for multiple inheritance.  When adding thunk
    % support, Cory decided to allow the second entry to differ so long as it resolved to the
    % same place.  It's unclear if this is really correct.

    forall(factMethodInVFTable(OtherVFTable, _Offset, Method1),
           reasonVFTableBelongsToClass(OtherVFTable, _ObjOffset2, Class2)),

    find(Method1, Class1),

    logtraceln('Proposing ~Q.', factMergeClasses_B(Method1, VFTable, Class1, Class2)),
    checkMergeClasses(Class1, Class2).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesB'),
    minof((Class, Method),
          guessMergeClassesB(Class, Method)),
    !,
    OneTuple=[(Class, Method)],
    logtraceln('Proposing ~Q.', factMergeClasses_B(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).


% This rule makes guesses about whether to assign methods to the derived class or the base
% class.  Right now it's an arbitrary guess (try the derived class first), but we can probably
% add a bunch of rules using class sizes and vftable sizes once the size rules are cleaned up a
% litte.  These rules are not easily combined in the "problem upstream" pattern because of the
% way Constructor is unified with different parameters of factDerviedConstructor, and it's not
% certain that the method is assigned to eactly one of those two anyway.  There's still the
% possibilty that the method is on one of the base classes bases -- a scenario that we may not
% currently be making any guesses for.
% ED_PAPER_INTERESTING
guessMergeClassesC(Class1, Class2) :-
    factClassCallsMethod(Class1, Method),
    not(purecall(Method)), % Never merge purecall methods into classes.
    factDerivedClass(Class1, _BaseClass, _Offset),
    find(Method, Class2),
    logtraceln('Proposing ~Q.', factMergeClasses_C(Class1, Class2)),
    checkMergeClasses(Class1, Class2).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesC'),
    minof((Class, Method),
          guessMergeClassesC(Class, Method)),
    !,
    OneTuple=[(Class, Method)],
    logtraceln('Proposing ~Q.', factMergeClasses_C(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).

% If that didn't work, maybe the method belongs on the base instead.
% ED_PAPER_INTERESTING
guessMergeClassesD(Class1, Class2) :-
    factClassCallsMethod(Class1, Method),
    not(purecall(Method)), % Never merge purecall methods into classes.
    factDerivedClass(_DerivedClass, Class1, _Offset),
    find(Method, Class2),
    logtraceln('Proposing ~Q.', factMergeClasses_D(Class1, Class2)),
    checkMergeClasses(Class1, Class2).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesD'),
    minof((Class, Method),
          guessMergeClassesD(Class, Method)),
    !,
    OneTuple=[(Class, Method)],
    logtraceln('Proposing ~Q.', factMergeClasses_D(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).

% And finally just guess regardless of derived class facts.
% ED_PAPER_INTERESTING
guessMergeClassesE(Class1, Class2) :-
    factClassCallsMethod(Class1, Method),
    not(purecall(Method)), % Never merge purecall methods into classes.
    % Same reasoning as in guessMergeClasses_B...
    not(symbolProperty(Method, virtual)),
    find(Method, Class2),
    logtraceln('Proposing ~Q.', factMergeClasses_E(Class1, Class2)),
    checkMergeClasses(Class1, Class2).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesE'),
    minof((Class, Method),
          guessMergeClassesE(Class, Method)),
    !,
    OneTuple=[(Class, Method)],
    logtraceln('Proposing ~Q.', factMergeClasses_E(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).

% If we have VFTable that is NOT associated with a class because there's no factVFTableWrite,
% factClassCallsMethod is not true...  The problem here is that we don't which method call
% which other methods (the direction of the call).  But we still have a very strong suggestion
% that methods in the VFTable are related in someway.  As a guessing rule a reasonable
% compromize is to say that any class that is still assigned to itself, is better off (from an
% edit distance perspective) grouped with the otehr methods.
guessMergeClassesF(Class, Method1) :-
    % There are two different entries in the same VFTable...
    factMethodInVFTable(VFTable, _Offset1, Method1),

    % One of the methods is in a class all by itself right now.
    findall(Method1, [Method1]),

    factMethodInVFTable(VFTable, _Offset2, Method2),
    iso_dif(Method1, Method2),
    % Follow thunks for both entries.  What does it mean if the thunks differed but the methods
    % did not?  Cory's not sure right now, but this is what the original rule did.
    iso_dif(Method1, Method2),

    % So go ahead and merge it into this class..
    find(Method2, Class),
    logtraceln('Proposing ~Q.', factMergeClasses_F(Class, Method1)),
    checkMergeClasses(Class, Method1).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesF'),
    minof((Class, Method),
          guessMergeClassesF(Class, Method)),
    !,
    OneTuple=[(Class, Method)],
    logtraceln('Proposing ~Q.', factMergeClasses_F(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).

% Try guessing that a VFTable belongs to a method.

% Say that a VFTable is installed by multiple methods.  If all of
% these methods are on the same class, it's a fair bet that the
% VFTable corresponds to that class.  This is implemented in
% reasonVFTableBelongsToClass.  But if the methods are not (currently)
% known to be on the same class, it's less clear what to do.  One
% situation we've observed is when a destructor is not merged.  There
% is some ambiguity because destructors are optimized more.  If a
% destructor installs a VFTable, we can't tell if the destructor is
% for that VFTable's class, or if the destructor is on a derived class
% (and the base destructor was inlined).  This guess identifies this
% situation.  We initially guess that the two class fragments are on
% the same class.  If that fails, we guess that the class identified
% by the destructor is derived from the other class.

% XXX: We may be able to do additional reasoning based on whether the
% classes have bases or not.  But this is probably handled by sanity
% checks too
guessMergeClassesG(Class1, Class2) :-
    % A constructor/destructor installs a VFTable
    factVFTableWrite(_Insn, Method, Offset, VFTable),
    find(Method, Class1),

    % This guessing rule is only for destructors, because
    % VFTableOverwrite logic works for constructors (see
    % reasonVFTableBelongsToClass).
    factNOTConstructor(Method),

    % Which other classes also install this VFTable
    setof(Class,
          Insn2^Offset2^Method2^(
              factVFTableWrite(Insn2, Method2, Offset2, VFTable),
              not(factVFTableOverwrite(Method2, _OtherVFTable, VFTable, Offset2)),
              find(Method2, Class),
              iso_dif(Class1, Class)),
          ClassSet),

    logdebugln('~Q is installed by destructor ~Q and these other classes: ~Q',
               [factVFTableWrite(Method, Offset, VFTable), Method, ClassSet]),

    (ClassSet = [Class2]
     ->
         checkMergeClasses(Class1, Class2),
         logdebugln('guessMergeClassesG had one candidate class: ~Q.', [Class2])
     ;
     % We will merge with the largest class
     % XXX: This could be implemented more efficiently using a maplist/2 and a sort.
     % Select a class
     member(Class2, ClassSet),
     % How big is it?
     numberOfMethods(Class2, Class2Size),
     % There is no one bigger
     forall(member(OtherClass, ClassSet),
            (numberOfMethods(OtherClass, OtherClassSize),
             not(OtherClassSize > Class2Size))),

     checkMergeClasses(Class1, Class2),
     logdebugln('guessMergeClassesG had more than one candidate class.  Merging with the largest class ~Q.', [Class2])
    ).

guessMergeClasses(Out) :-
    reportFirstSeen('guessMergeClassesG'),
    minof((Class1, Class2),
          guessMergeClassesG(Class1, Class2)),
    !,
    OneTuple=[(Class1, Class2)],
    logtraceln('Proposing ~Q.', factMergeClasses_G(OneTuple)),
    Out = tryBinarySearch(tryMergeClasses, tryNOTMergeClasses, OneTuple, 1).


checkMergeClasses(Method1, Method2) :-
    iso_dif(Method1, Method2),
    find(Method1, Class1),
    find(Method2, Class2),
    % They're not already on the same class...
    iso_dif(Class1, Class2),
    % They're not already proven NOT to be on the same class.
    doNotGuessHelper(factNOTMergeClasses(Class1, Class2),
                     factNOTMergeClasses(Class2, Class1)),
    % XXX: Check factMergeClasses?
    % Now relationships between the classes are not allowed either.
    not(reasonClassRelationship(Class1, Class2)),
    not(reasonClassRelationship(Class2, Class1)).

tryMergeClasses((Method1, Method2)) :- tryMergeClasses(Method1, Method2).
% If we are merging classes that have already been merged, just ignore it.
tryMergeClasses(Method1, Method2) :-
    find(Method1, Class1),
    find(Method2, Class2),
    Class1 = Class2,
    !.
tryMergeClasses(Method1, Method2) :-
    countGuess,
    find(Method1, Class1),
    find(Method2, Class2),
    loginfoln('Guessing ~Q.', mergeClasses(Class1, Class2)),
    mergeClasses(Class1, Class2),
    try_assert(guessedMergeClasses(Class1, Class2)).

tryNOTMergeClasses((Class1, Class2)) :- tryNOTMergeClasses(Class1, Class2).
tryNOTMergeClasses(Method1, Method2) :-
    countGuess,
    find(Method1, Class1),
    find(Method2, Class2),
    loginfoln('Guessing ~Q.', factNOTMergeClasses(Class1, Class2)),
    try_assert(factNOTMergeClasses(Class1, Class2)),
    try_assert(guessedNOTMergeClasses(Class1, Class2)).

% --------------------------------------------------------------------------------------------
% Try guessing that method is a real destructor.
% --------------------------------------------------------------------------------------------
guessRealDestructor(Out) :-
    reportFirstSeen('guessRealDestructor'),
    minof(Method,
          (likelyDeletingDestructor(DeletingDestructor, Method),
           % Require that we've already confirmed the deleting destructor.
           factDeletingDestructor(DeletingDestructor),
           doNotGuessHelper(factRealDestructor(Method),
                            factNOTRealDestructor(Method)))),

    Out = tryOrNOTRealDestructor(Method).

%% tryOrNOTRealDestructor(Method) :-
%%     likelyDeletingDestructor(DeletingDestructor, Method),
%%     % Require that we've already confirmed the deleting destructor.
%%     factDeletingDestructor(DeletingDestructor),
%%     doNotGuessHelper(factRealDestructor(Method),
%%                      factNOTRealDestructor(Method)),
%%     countGuess,
%%     (tryRealDestructor(Method);
%%      tryNOTRealDestructor(Method)).

% Establish that the candidate meets minimal requirements.
minimalRealDestructor(Method) :-
    possibleDestructor(Method),
    doNotGuessHelper(factRealDestructor(Method),
                     factNOTRealDestructor(Method)),

    % Trying a different approach to blocking singletons here.  Many singletons have no
    % interprocedural flow at all, and so also have no call before AND no calls after.
    % This causes a significant regression (at least by itself), F=0.43 -> F=0.36.
    % Even as an ordering rule this appears to be harmful... F=0.46 -> F=0.42 why?
    % not(noCallsBefore(Method)),

    % Destructors can't take multiple arguments (well except for when they have virtual bases),
    % but this should at least get us closer...
    not((
               funcParameter(Method, Position, _SV),
               iso_dif(Position, ecx)
       )),

    % There must be at least one other method besides this one on the class.  There's a strong
    % tendency to turn every singleton method into real destructor without this constraint.
    find(Method, Class),
    find(Other, Class),
    iso_dif(Other, Method),
    true.

% Prioritize methods called by deleteing destructors.
guessFinalRealDestructor(Out) :-
    minimalRealDestructor(Method),
    callTarget(_Insn, OtherDestructor, Method),
    factDeletingDestructor(OtherDestructor),
    Out = tryOrNOTRealDestructor(Method).

% Prioritize methods that call other real destructors.
guessFinalRealDestructor(Out) :-
    minimalRealDestructor(Method),
    callTarget(_Insn, Method, OtherDestructor),
    factRealDestructor(OtherDestructor),
    Out = tryOrNOTRealDestructor(Method).

% Prioritize methods that do not call delete to avoid confusion with deleting destructors.
% This eliminates a couple of false positives in the fast test suite.
guessFinalRealDestructor(Out) :-
    minimalRealDestructor(Method),
    not(insnCallsDelete(_Insn, Method, _SV)),
    Out = tryOrNOTRealDestructor(Method).

% Guess if it meets the minimal criteria.
guessFinalRealDestructor(Out) :-
    minimalRealDestructor(Method),
    Out = tryOrNOTRealDestructor(Method).

tryOrNOTRealDestructor(Method) :-
    countGuess,
    tryRealDestructor(Method);
    tryNOTRealDestructor(Method);
    logwarnln('Something is wrong upstream: ~Q.', invalidRealDestructor(Method)),
    fail.

tryRealDestructor(Method) :-
    loginfoln('Guessing ~Q.', factRealDestructor(Method)),
    try_assert(factRealDestructor(Method)),
    try_assert(guessedRealDestructor(Method)).

tryNOTRealDestructor(Method) :-
    loginfoln('Guessing ~Q.', factNOTRealDestructor(Method)),
    try_assert(factNOTRealDestructor(Method)),
    try_assert(guessedNOTRealDestructor(Method)).

% --------------------------------------------------------------------------------------------
% Try guessing that method is a deleting destructor.
% --------------------------------------------------------------------------------------------

% The criteria for guessing deleting destructors...

% This rule guesses we're a destructor because we install a vftable and appear to be virtual.
% We can't tell if we're a deleting or real destructor, but if we guess wrong we'll almost
% always know immediately because of reasonNOTRealDestructor_H and
% reasonNOTDeletingDestructor_F.
likelyAVirtualDestructor(Method) :-
    % Standard destructor requirement
    noCallsAfter(Method),
    % We install a vftable
    certainConstructorOrDestructor(Method),
    % And we're probably a virtual method
    possiblyVirtual(Method).

guessDeletingDestructor(Out) :-
    reportFirstSeen('guessDeletingDestructor'),
    setof(Method,
          (likelyAVirtualDestructor(Method),
           doNotGuessHelper(factDeletingDestructor(Method),
                            factNOTDeletingDestructor(Method))),
          MethodSet),
    !,
    Out = tryBinarySearch(tryDeletingDestructor, tryNOTDeletingDestructor, MethodSet).

guessDeletingDestructor(Out) :-
    minof(Method,
          (likelyDeletingDestructor(Method, _RealDestructor),
           doNotGuessHelper(factDeletingDestructor(Method),
                            factNOTDeletingDestructor(Method)))),
    !,
    Out = tryOrNOTDeletingDestructor(Method).

tryOrNOTDeletingDestructor(Method) :-
    %likelyDeletingDestructor(Method, _RealDestructor),
    doNotGuessHelper(factDeletingDestructor(Method),
                     factNOTDeletingDestructor(Method)),
    (
        tryDeletingDestructor(Method);
        tryNOTDeletingDestructor(Method);
        logwarnln('Something is wrong upstream: ~Q.', invalidDeletingDestructor(Method)),
        fail
    ).

guessFinalDeletingDestructor(Out) :-
    reportFirstSeen('guessFinalDeletingDestructor'),
    possibleDestructor(Method),
    doNotGuessHelper(factDeletingDestructor(Method),
                     factNOTDeletingDestructor(Method)),

    insnCallsDelete(_Insn2, Method, _SV),

    % guessDeletingDestructor requires a call to a real destructor.  This rule relaxes that a
    % bit, by ensuring we don't call any non-real destructors.  So calling a real destructor
    % will trigger this rule, but it is not necessary.
    not((
               callTarget(_Insn1, Method, Called),
               not(factRealDestructor(Called))
       )),

    !,
    Out = tryOrNOTDeletingDestructor(Method).

%
guessFinalDeletingDestructor(Out) :-
    % Establish that the candidate meets minimal requirements.
    possibleDestructor(Method),
    doNotGuessHelper(factDeletingDestructor(Method),
                     factNOTDeletingDestructor(Method)),

    % The calls delete requirement was what was needed to keep false positives down.
    insnCallsDelete(_DeleteInsn, Method, _SV),

    % If the method occurs twice in a single VFTable, wildly guess that it's a deleting
    % destructor based entirely on a common phenomenon in the Visual Studio compiler.

    % There are two thunks to Method in VFTable
    factMethodInVFTable(VFTable, Offset1, Method),
    % XXX: By binding to _Other_Method instead of Method on the next line, we are preserving a
    % known bug because it seems to produce better results for destructors.
    factMethodInVFTable(VFTable, Offset2, _Other_Method),
    iso_dif(Offset1, Offset2),

    % For this rule to apply, there has to be two different entries that thunk to Method
    factVFTableEntry(VFTable, Offset1, Entry1),
    factVFTableEntry(VFTable, Offset2, Entry2),

    % We are not sure if the entry actually has to differ or not.  We should experiment with
    % whether removing the next line improves accuracy.
    iso_dif(Entry1, Entry2),

    !,
    Out = tryOrNOTDeletingDestructor(Method).

tryDeletingDestructor(Method) :-
    loginfoln('Guessing ~Q.', factDeletingDestructor(Method)),
    try_assert(factDeletingDestructor(Method)),
    try_assert(guessedDeletingDestructor(Method)).

tryNOTDeletingDestructor(Method) :-
    loginfoln('Guessing ~Q.', factDeletingDestructor(Method)),
    try_assert(factNOTDeletingDestructor(Method)),
    try_assert(guessedNOTDeletingDestructor(Method)).

% A helper for guessing deleting destructors.
:- table likelyDeletingDestructor/2 as incremental.

likelyDeletingDestructor(_, RealDestructor) :-
    ground(RealDestructor),
    throw_with_backtrace(error(uninstantiation_error(RealDestructor),
                               likelyDeletingDestructor/2)).

likelyDeletingDestructor(DeletingDestructor, RealDestructor) :-
    % Deleting destructors must call the real destructor (we think).  Usually offset is zero,
    % but there are some unusual cases where there are multiple calls to real destructors, and
    % only one has offset zero and we missed it because we're not handling imported OO methods
    % correctly.  A cheap hack to just be a little looser here and accept any calls to
    % destructors. Note we do NOT bind _RealDestructor.  See note below.
    validFuncOffset(_RealDestructorInsn1, DeletingDestructor, _RealDestructor, _Offset1),

    % This indicates that the method met some basic criteria in C++.
    possibleDestructor(DeletingDestructor),
    % That's not already certain to NOT be a deleting destructor.
    not(factNOTDeletingDestructor(DeletingDestructor)),
    % And the deleting destructor must also call delete (we think), since that's what makes it
    % deleting.  Using this instead of the more complicated rule below led toa very slight
    % improvement in the fast test suite F=0.43 -> F=0.44.
    insnCallsDelete(DeleteInsn, DeletingDestructor, _SV),
    % This condition is complicated.  We want to ensure that the thing actually being deleted
    % is the this-pointer passed to the deleting destructor.  But the detection of parameters
    % to delete is sometimes complicated, and a non-trivial number of our facts are still
    % reporting "invalid".  While the real fix is to always have correct parameter values for
    % delete(), in the mean time lets try accepting an fact-generation failure as well, but not
    % a pointer that's known to be unrelated).

    % This rule currently needs to permit the slightly different ECX parameter standard.  An
    % example is std::basic_filebuf:~basic_filebuf in Lite/oo.
    (callingConvention(DeletingDestructor, '__thiscall'); callingConvention(DeletingDestructor, 'invalid')),
    funcParameter(DeletingDestructor, 'ecx', ThisPtr),
    (
        insnCallsDelete(DeleteInsn, DeletingDestructor, ThisPtr);
        insnCallsDelete(DeleteInsn, DeletingDestructor, invalid)
    ),

    % Phew. Everything up until this point has been about the _deleting destructor_.  We
    % intentionally did _not_ bind RealDestructor.  Now that we've checked out the deleting
    % destructor, let's look for any possible real destructor.
    validFuncOffset(_RealDestructorInsn2, DeletingDestructor, RealDestructor, _Offset2),

    % And while it's premature to require the real destructor to be certain, it shouldn't be
    % disproven.
    possibleDestructor(RealDestructor),
    not(factNOTRealDestructor(RealDestructor)),
    true.

%% Local Variables:
%% mode: prolog
%% End:
