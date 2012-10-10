function convertElementTestToMatchingOptions(select: string): TXQPathMatchingKinds;
begin
  if select = 'node' then
    exit([qmText,qmComment,qmElement,qmProcessingInstruction,qmAttribute])
  else if select = 'text' then exit([qmText])
  else if select = 'comment' then exit([qmComment])
  else if select = 'element' then exit([qmElement,qmExcludeRoot])
  else if select = 'processing-instruction' then exit([qmProcessingInstruction])
  else raise Exception.Create('Unknown element test: '+select);
end;

function convertMatchingOptionsToMatchedTypes(const qmt: TXQPathMatchingKinds): TTreeElementTypes;
begin
  result := [];
  if qmText in qmt then include(result, tetText);
  if qmElement in qmt then include(result, tetOpen);
  if qmComment in qmt then include(result, tetComment);
  if qmProcessingInstruction in qmt then include(result, tetProcessingInstruction);
  if qmAttribute in qmt then begin result += [tetAttributeName, tetAttributeValue]; end;
end;

{ TXQTermReadProperty }

constructor TXQTermReadObjectProperty.create(apropname: string);
begin
  propname := apropname;
end;

function TXQTermReadObjectProperty.evaluate(const context: TEvaluationContext): TXQValue;
var
  obj: TXQValue;
begin
  if length(children) = 0 then raiseEvaluationError('Found no term to read property from');
  if length(children) > 1 then raiseEvaluationError('Can only read property from one term');
  obj:=children[0].evaluate(context);
  if not (obj is TXQValueObject) then raiseEvaluationError('Expected object, got: '+obj.toString);
  result := TXQValueObject(obj).getClone(propname);
  obj.free;
end;

{ TXQTermIf }

function TXQTermIf.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if length(children)<>3 then raiseEvaluationError('if must have 3 arguments');
  if children[0].evaluate(context).toBoolean then result:=children[1].evaluate(context)
  else result:=children[2].evaluate(context);
end;

{ TXQTermFilterSequence }

constructor TXQTermFilterSequence.create(seq: TXQTerm; filter: TXQTerm);
begin
  push(seq);
  push(filter);
end;

function TXQTermFilterSequence.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if length(children) <> 2 then raiseEvaluationError('Invalid [] sequence filter');
  result := children[0].evaluate(context);
  context.sender.filterSequence(result, children[1], context);
  xqvalueSeqSqueeze(result);
end;

function TXQTermFilterSequence.toQueryCommand: TXQPathMatchingStep;
begin
  if length(children) <> 2 then raiseEvaluationError('invalid [] construct');
  result := children[0].toQueryCommand;
  setlength(result.filters, length(result.filters)+1);
  result.filters[high(result.filters)] := children[1];
end;

procedure TXQTermFilterSequence.addToQueryList(var path: TXQPathMatching);
begin
  if length(children) <> 2 then raiseEvaluationError('Invalid [] sequence filter');

  children[0].addToQueryList(path);
  setlength(path[high(path)].filters, length(path[high(path)].filters) + 1);
  path[high(path)].filters[high(path[high(path)].filters)] := children[1];
end;

{ TXQTermDefineVariable }

constructor TXQTermDefineVariable.create(varname: TXQTerm; value: TXQTerm);
begin
  if varname is TXQTermNodeMatcher then variablename := TXQTermNodeMatcher(varname).debugTermToString
  else if varname is TXQTermVariable then variablename := TXQTermVariable(varname).value
  else raiseParsingError('Invalid term to assign a variable to: '+varname.debugTermToString);
  varname.Free;
  push(value);
end;

function TXQTermDefineVariable.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if not assigned(context.sender.OnDefineVariable) then raiseEvaluationError(':= can''t be used without a method assigned to the OnDefineVariable event');
  if length(children) = 0 then raiseEvaluationError('Value missing');
  if length(children) > 1 then raiseEvaluationError('Only one value can be assigned to a variable');
  result := children[0].evaluate(context);

  context.sender.OnDefineVariable(self, variablename, result.clone);
end;

{ TXQTermType }

constructor TXQTermSequenceType.create(const avalue: string);
begin
  init(avalue);
end;

function TXQTermSequenceType.evaluate(const context: TEvaluationContext): TXQValue;
begin
  result := TXQValueFunction.create(self); //return a function returning this term. This allows returning the type itself, without having a "type"-type in the type system.
end;

procedure TXQTermSequenceType.init(const s: string);
var occurenceLength: integer;
  index: Integer;
begin
  if s = '' then raise Exception.Create('no type');
  serializedValue:=s;
  if pos('(', s) > 0 then begin
    if pos('()', s) = 0 then raise Exception.Create('Element tests with arguments are not supported');
  end;
  allowNone:=false;
  allowMultiple:=false;
  if s = 'empty-sequence()' then kind:=tikNone
  else begin
    occurenceLength := 1;
    case s[length(s)] of
      '?': allowNone:=true;
      '+': allowMultiple:=true;
      '*': begin allowNone:=true; allowMultiple:=true; end;
      else occurenceLength := 0;
    end;
    if strBeginsWith(s, 'item()') then
      kind:=tikAny
    else if pos('()', s) > 0 then begin
      kind:=tikElementTest;
      name:=copy(s,1,length(s)-occurenceLength);
      delete(name, pos('(', name), 2);
      matchedTypes := convertMatchingOptionsToMatchedTypes(convertElementTestToMatchingOptions(name));
    end else begin
      kind:=tikAtomic;
      name:=copy(s,1,length(s)-occurenceLength);
      index := types.IndexOf(name);
      if index < 0 then raise Exception.Create('Unknown type: '+name);
      atomicTypeInfo := TXQValueClass(types.Objects[index]);
    end;
  end;
end;

function TXQTermSequenceType.isSingleType(): boolean;
begin
  result := (kind = tikAtomic) and not allowMultiple;
end;

function TXQTermSequenceType.castableAsBase(v: TXQValue): boolean;
begin
  if v.isUndefined then result := allowNone
  else if v.getSequenceCount > 1 then result := false
  else if v is TXQValueSequence then result := TXQValueSequence(v).seq[0].canConvertToType(atomicTypeInfo)
  else result := v.canConvertToType(atomicTypeInfo)
end;

function TXQTermSequenceType.castAs(v: TXQValue): TXQValue;
begin
  if not isSingleType() then raise exception.Create('need singletype for cast as');
  if not castableAsBase(v) then raise exception.Create('impossible cast as');
  result := atomicTypeInfo.createFromValue(v);
end;

function TXQTermSequenceType.castableAs(v: TXQValue): boolean;
begin
  if not isSingleType() then raise exception.Create('need singletype for castable as');
  result := castableAsBase(v);
  v.free;
end;

function TXQTermSequenceType.instanceOf(ta: TXQValue): boolean;
begin
  result := instanceOfBase(ta);
  ta.free;
end;

function TXQTermSequenceType.instanceOfBase(ta: TXQValue): boolean;
  function instanceOfSingleType(sub: TXQValue): boolean;
  begin
    case kind of
      //tikAny, tikNone: ; //handled before
      tikAtomic: result := sub.instanceOf(atomicTypeInfo);
      tikElementTest: begin
        if (not (sub is TXQValueNode)) or (TXQValueNode(sub).node = nil) then exit(false);
        result  := TXQValueNode(sub).node.typ in matchedTypes;
      end;
    end;
  end;
var
  seq: TXQVList;
  i: Integer;
  count: Integer;
begin
  //compare count with sequence count
  if kind = tikNone then exit(ta.isUndefined);
  count := ta.getSequenceCount;
  if ((count = 0) and not allowNone) or
     ((count > 1) and not allowMultiple) then
    exit(false);
  if (count = 0) then
    exit(true);
  //compare item type
  if kind = tikAny then
    exit(true);
  if not (ta is TXQValueSequence) then exit(instanceOfSingleType(ta))
  else begin
    seq := TXQValueSequence(ta).seq;
    result := true;
    for i:=0 to seq.Count - 1 do begin
      result := result and instanceOfSingleType(seq[i]);
      if not result then exit;
    end;
  end
end;
{ TXQTermSequence }

function TXQTermSequence.evaluate(const context: TEvaluationContext): TXQValue;
var
  i: Integer;
begin
  if length(children) = 0 then exit(xqvalue);
  if length(children) = 1 then exit(children[0].evaluate(context));
  result := TXQValueSequence.create(length(children));
  for i := 0 to high(children) do
    TXQValueSequence(result).addChild(children[i].evaluate(context));
end;

{ TXQTermSomeEvery }

constructor TXQTermSomeEvery.create(every: boolean);
begin
  isEvery:=every;
end;

function TXQTermSomeEvery.evaluate(const context: TEvaluationContext): TXQValue;
var tempContext:TEvaluationContext;
  function evaluateSomeEvery(const pos:integer): boolean;
  var tempSeq: TXQValue;
      i:integer;
  begin
    if pos = high(children) then exit(children[pos].evaluate(tempContext).toBoolean);
    if not (children[pos] is TXQTermVariable) then raiseEvaluationError('Expected variable, but got '+children[pos].debugTermToString);

    tempSeq:=children[pos+1].evaluate(tempContext);
    case tempSeq.kind of
      pvkUndefined: begin
        result := isEvery;
        tempSeq.Free;
      end;
      pvkSequence: begin
        result:=isEvery;
        for i:=TXQValueSequence(tempSeq).seq.Count-1 downto 0 do begin
          tempContext.temporaryVariables.pushAll;
          tempContext.temporaryVariables.addVariable(TXQTermVariable(children[pos]).value, TXQValueSequence(tempSeq).seq[i]);
          TXQValueSequence(tempSeq).seq.Delete(i);
          if evaluateSomeEvery(pos+2) <> (isEvery) then begin
            tempContext.temporaryVariables.popAll;
            result := not isEvery;
            break;
          end;
          tempContext.temporaryVariables.popAll;
        end;
        tempSeq.Free;
      end;
      else begin
        tempContext.temporaryVariables.pushAll;
        tempContext.temporaryVariables.addVariable(TXQTermVariable(children[pos]).value, tempSeq);
        result := evaluateSomeEvery(pos+2);
        tempContext.temporaryVariables.popAll;
      end;
    end;
  end;

begin
  tempContext:=context;
  if context.temporaryVariables=nil then begin
    tempContext.temporaryVariables:=TXQVariableChangeLog.create();
    tempContext.temporaryVariables.allowObjects:=tempContext.sender.VariableChangelog.allowObjects;
  end;
  result:=xqvalue(evaluateSomeEvery(0));
  xqvalueSeqSqueeze(result);
  if context.temporaryVariables = nil then FreeAndNil(tempContext.temporaryVariables) //iff context.temporaryVariables = nil, we created the change log here
end;

{ TXQTermFor }

type TOrderedTuple = class
  orders: array of TXQValue;
  result: TXQValue;
end;
  TFlowerSortingData = record
    flower: TXQTermFlower;
    collations: array of TXQCollation;
    context: ^TEvaluationContext;
  end;
  PFlowerSortingData = ^TFlowerSortingData;

function flowerTupleCompareFunction(data: TObject; xa, xb: pointer): longint;
var meta: PFlowerSortingData;

  function isGreaterThan(w, v: txqvalue; emptyLeast: boolean; const collation: TXQCollation): boolean;
  var
    temp: integer;
  begin
    result := false;
    if emptyLeast then begin
      if v.isUndefined and not w.isUndefined then
        exit(true);
      if ((v is TXQValueDecimal) and IsNan(TXQValueDecimal(v).value)) and not w.isUndefined and not ((w is TXQValueDecimal) and IsNan(TXQValueDecimal(w).value)) then
        exit(true);
    end else begin
      if w.isUndefined and not v.isUndefined then
        exit(true);
      if ((w is TXQValueDecimal) and IsNan(TXQValueDecimal(w).value)) and not v.isUndefined and not ((v is TXQValueDecimal) and IsNan(TXQValueDecimal(v).value)) then
        exit(true);
    end;

    if (collation <> nil) and (v is TXQValueString) and (w is TXQValueString) then
      exit(collation.compare(v.asString, w.asString) < 0);
    temp := meta^.context^.compareAtomicBase(v,w) ;
    result := (temp <> -2) and (temp < 0);
  end;

var
  a, b: TOrderedTuple;
  orders: array of TXQTermFlowerOrder;
  i: Integer;
  emptyLeast: Boolean;
begin
  meta := PFlowerSortingData(data);
  orders := meta^.flower.orders;
  a := TOrderedTuple(ppointer(xa)^);
  b := TOrderedTuple(ppointer(xb)^);

  result := 0;

  for i := 0 to high(orders) do begin
    emptyLeast := (orders[i].emptyOrder = xqfoEmptyLeast) or ((orders[i].emptyOrder = xqfoStatic) and (meta^.context^.emptyOrderSpec = xqfoEmptyLeast));
    if isGreaterThan(a.orders[i], b.orders[i], emptyLeast, meta^.collations[i]) then result := 1
    else if isGreaterThan(b.orders[i], a.orders[i], emptyLeast, meta^.collations[i]) then result := -1;
    if orders[i].descending then result := -Result;
    if result <> 0 then exit;
  end;
end;

function TXQTermFlower.evaluate(const context: TEvaluationContext): TXQValue;
var
  tempContext: TEvaluationContext;
  sortingCache: TFPList;
  finalResult: TXQValue;
  oldVarCount: Integer;
  procedure evaluateForLoop(const pos:integer);
    procedure continueWithValue(v: TXQValue; index: integer = 1);
    begin
      tempContext.temporaryVariables.pushAll;
      //sequenceTyp: TXQTermType;
      tempContext.temporaryVariables.addVariable(vars[pos].varname, v);
      if (vars[pos].sequenceTyp <> nil) and not (vars[pos].sequenceTyp.instanceOfBase(v)) then
        raiseEvaluationError('Invalid variable type, expected: type '+vars[pos].sequenceTyp.serializedValue+' got value '+v.asString);
      if vars[pos].positionVarname <> '' then ;
        tempContext.temporaryVariables.addVariable(vars[pos].positionVarname, xqvalue(index));
      evaluateForLoop(pos+1);
      tempContext.temporaryVariables.popAll;
    end;

   var tempSeq: TXQValue;
       i:integer;
       tuple: TOrderedTuple;
   begin
     if pos = length(vars) then begin
       if (where <> nil) and not where.evaluate(tempContext).toBoolean then
         exit;

       if sortingCache = nil then begin
         xqvalueSeqAdd(finalResult, returned.evaluate(tempContext));
         exit;
       end else begin
         tuple := TOrderedTuple.Create;
         tuple.result := returned.evaluate(tempContext);
         setlength(tuple.orders, length(orders));
         for i:= 0 to high(orders) do
           tuple.orders[i] := orders[i].expr.evaluate(tempContext);
         sortingCache.Add(tuple);
         exit;
       end;
     end;

     tempSeq:=vars[pos].expr.evaluate(tempContext);

     if vars[pos].kind = xqfkLet then
       continueWithValue(tempSeq)
     else case tempSeq.kind of
       pvkUndefined: tempSeq.Free;
       pvkSequence: begin
         for i:=0 to TXQValueSequence(tempSeq).seq.Count-1 do
           continueWithValue(TXQValueSequence(tempSeq).seq[i], i + 1);
         TXQValueSequence(tempSeq).freeNonRecursive;
       end
       else continueWithValue(tempSeq);
     end;
   end;
var i, j: Integer;
    sortingData: TFlowerSortingData;

begin
  tempContext:=context;
  if context.temporaryVariables=nil then begin
    tempContext.temporaryVariables:=TXQVariableChangeLog.create();
    tempContext.temporaryVariables.allowObjects:=tempContext.sender.VariableChangelog.allowObjects;
  end;

  oldVarCount := tempContext.temporaryVariables.count;

  finalResult := nil;
  if length(orders) = 0 then sortingCache := nil
  else sortingCache := tfplist.Create;

  evaluateForLoop(0);

  if sortingCache <> nil then begin
    if sortingCache.Count > 0 then begin
      sortingData.flower:=self;
      sortingData.context:=@tempContext;
      setlength(sortingData.collations, length(orders));
      for i := 0 to high(orders) do
        if orders[i].collation = '' then sortingData.collations[i] := nil
        else sortingData.collations[i] := context.sender.getCollation(orders[i].collation);
      stableSort(ppointer(sortingCache.List^), ppointer(sortingCache.List^) + (sortingCache.Count-1) , sizeof(pointer), @flowerTupleCompareFunction, TObject(@sortingData));
      for i := 0 to sortingCache.Count - 1 do begin
        xqvalueSeqAdd(finalResult, TOrderedTuple(sortingCache[i]).result);
        for j := 0 to high(TOrderedTuple(sortingCache[i]).orders) do
          TOrderedTuple(sortingCache[i]).orders[j].Free;
        TOrderedTuple(sortingCache[i]).Free;
      end;
    end;
    sortingCache.free;
  end;

  if finalResult = nil then result := TXQValueUndefined.create
  else result := finalResult;
  xqvalueSeqSqueeze(result);
  if context.temporaryVariables = nil then FreeAndNil(tempContext.temporaryVariables) //iff context.temporaryVariables = nil, we created the change log here
end;

destructor TXQTermFlower.destroy;
var
  i: Integer;
begin
  for i:=0 to high(vars) do begin
    vars[i].expr.Free;
    vars[i].sequenceTyp.Free;
  end;
  for i:= 0 to high(orders) do
    orders[i].expr.Free;
  where.Free;
  returned.Free;
  inherited destroy;
end;

{ TXQTermNamedFunction }

constructor TXQTermNamedFunction.create(const akind: TXQTermNamedFunctionKind; const aindex: integer);
begin
  kind := akind;
  index := aindex;
end;

constructor TXQTermNamedFunction.create(const name: string);
begin
  if not findKindIndex(name, kind, index, true) then raiseParsingError('Unknown function: '+name);
end;

constructor TXQTermNamedFunction.create(const name: string; args: array of TXQTerm);
begin
  create(name);
  push(args);
end;

class function TXQTermNamedFunction.createIfExists(const name: string; checkForOperators: boolean): TXQTermNamedFunction;
var akind: TXQTermNamedFunctionKind;
    aindex: integer;
begin
  if not findKindIndex(name, akind, aindex, checkForOperators) then exit(nil);
  result := TXQTermNamedFunction.Create(akind, aindex);
end;

function TXQTermNamedFunction.evaluate(const context: TEvaluationContext): TXQValue;
var
  evilkids: TXQVArray;
begin
  evaluateChildren(context, evilkids);

  assert(index >= 0);

  case kind of
    xqfkBasic: begin
      result := xqvalue();
      PXQBasicFunctionInfo(basicFunctions.Objects[index])^.func(evilkids, result)
    end;
    xqfkComplex: begin
      result := xqvalue();
      PXQComplexFunctionInfo(complexFunctions.Objects[index])^.func(context, evilkids, result);
    end;
    xqfkWrappedOperator: begin
      if length(evilkids) <> 2 then raiseEvaluationError('Need two arguments for function: op:' + binaryOpFunctions[index]);
      result := xqvalue();
      TXQBinaryOp(binaryOpFunctions.Objects[index])(context, evilkids[0], evilkids[1], result);
    end;
    xqfkTypeConstructor:
      result := TXQValueClass(types.Objects[index]).createFromValue(evilkids);

  end;
end;

procedure xqFunctionGeneralConstructor(args: array of TXQValue; var result: TXQValue);forward;

class function TXQTermNamedFunction.findKindIndex(const name: string; out akind: TXQTermNamedFunctionKind; out aindex: integer; checkForOps: boolean): boolean;
var
  i: Integer;
begin
  aindex := basicFunctions.IndexOf(name);
  if aindex >= 0 then begin
    if PXQBasicFunctionInfo(basicFunctions.Objects[aindex])^.func = @xqfunctionGeneralConstructor then begin
      akind:=xqfkTypeConstructor;
      aindex:=types.indexof(name);;
      exit(true);
    end;
    akind:=xqfkBasic;
    exit(true);
  end;

  aindex := complexFunctions.IndexOf(name);
  if aindex >= 0 then begin
    akind:=xqfkComplex;
    exit(true);
  end;

  aindex := -1;
  for i:=0 to  binaryOpFunctions.Count-1 do
    if strContains(name, binaryOpFunctions[i]) then begin
      aindex := i;
      akind := xqfkWrappedOperator;
      exit(true);
    end;;

  exit(false);
end;



{ TXQTermBinaryOp }

constructor TXQTermBinaryOp.create(const op: string; arg1: TXQTerm; arg2: TXQTerm);
begin
  index := binaryOps.IndexOf(op);
  if arg1 <> nil then begin
    push(arg1);
    if arg2 <> nil then push(arg2);
  end;
end;

constructor TXQTermBinaryOp.create(arg1: TXQTerm; const op: string; arg2: TXQTerm);
begin
  create(op, arg1, arg2);
end;

function TXQTermBinaryOp.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if length(children)<2 then raiseEvaluationError('Not enough subterms');
  if length(children)>2 then raiseEvaluationError('Too many subterms');

  result := xqvalue();

  if (index = binaryOps.IndexOf('/')) or (index = binaryOps.IndexOf('//')) then begin
    context.sender.evaluateAccessList(self, context, result);
    exit;
  end;

  operatorInfo^.func(context, children[0].evaluate(context), children[1].evaluate(context),result);
end;

function TXQTermBinaryOp.operatorInfo: PXQOperatorInfo;
begin
  if (index < 0) or (index >= binaryOps.Count) then raiseEvaluationError('Invalid bin op index');
  result := PXQOperatorInfo(binaryOps.Objects[index])
end;

procedure TXQTermBinaryOp.addToQueryList(var path: TXQPathMatching);
var
  isDoubleSlash: Boolean;
  last: Integer;
begin
  isDoubleSlash := (index = binaryOps.IndexOf('//'));
  if  not (isDoubleSlash or (index = binaryOps.IndexOf('/'))) then begin
    inherited addToQueryList(path);
    exit;
  end;

  children[0].addToQueryList(path);
  if isDoubleSlash then begin
    setlength(path, length(path) + 1);
    path[high(path)].typ:=qcSameOrDescendant;
    path[high(path)].matching:=[qmElement, qmText, qmComment, qmProcessingInstruction];
  end;
  children[1].addToQueryList(path);

  //optimization
  //two descendants following each other can be condensed to a single descendant (but this changes the indices of the sequence, so it only work if there are no numeric filters)
  last := high(path);
  if (path[last - 1].typ = qcSameOrDescendant) and (path[last - 1].matching = [qmElement, qmText, qmComment, qmProcessingInstruction]) and (length(path[last - 1].filters) = 0)
      and (path[last].typ in [qcDirectChild, qcDescendant]) and (length(path[last].filters) = 0) then begin
    path[last - 1] := path[last];
    path[last - 1].typ := qcDescendant;
    SetLength(path, last);
  end;
end;

{ TXQTermNodeMatcher }

constructor TXQTermNodeMatcher.Create(const avalue: string; asfunction: boolean);
begin
  axis := '';
  select := avalue;
  if strContains(select,'::') then axis:=strSplitGet('::',select);
  hadNamespace := strContains(select,':');
  if hadNamespace then  namespace:=strSplitGet(':',select);
  func := asfunction;
end;

function TXQTermNodeMatcher.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if (select = '.') and (context.SeqValue <> nil) then result := context.SeqValue.clone
  else if func and (axis = '') and (select = 'text') and (context.sender.TextElement<>nil) then result := xqvalue(context.sender.TextElement)
  else begin
    result := context.sender.evaluateSingleStepQuery(toQueryCommand,context);
    xqvalueSeqSqueeze(result);
  end;
end;

function TXQTermNodeMatcher.debugTermToString: string;
begin
  result := '';
  if axis <> '' then result += axis + '::';
  if namespace <> '' then result += namespace + ':';
  result += select;
end;

function TXQTermNodeMatcher.toQueryCommand: TXQPathMatchingStep;
  function getAxis(const axis: string): TXQPathMatchingAxis;
  begin
     //forward
     if (axis ='') or (axis='child') then exit(qcDirectChild);
     if axis='descendant' then exit(qcDescendant);
     if axis='self' then exit(qcSameNode);
     if axis='parent' then exit(qcDirectParent);
     //if axis='attribute' then exit(qcDescendant);
     if axis='descendant-or-self' then exit(qcSameOrDescendant);
     if axis='following-sibling' then exit(qcFollowingSibling);
     if axis='following' then exit(qcFollowing);

     //reverse
     if axis='ancestor' then exit(qcAncestor);
     if axis='preceding-sibling' then exit(qcPrecedingSibling);
     if axis='preceding' then exit(qcPreceding);
     if axis='ancestor-or-self' then exit(qcSameOrAncestor);
     raise EXQEvaluationException.Create('Unknown axis: '+axis);
  end;

begin
  if func then begin
    result.typ:=getAxis(axis);
    result.matching:=convertElementTestToMatchingOptions(select);
    if (length(children) > 0) then
      if (result.matching = [qmProcessingInstruction])  then begin
        if children[0] is TXQTermNodeMatcher then begin;
          if TXQTermNodeMatcher(children[0]).axis <> '' then raiseEvaluationError('axis within element test is not allowed');
          result.value := TXQTermNodeMatcher(children[0]).select;
        end else if children[0] is TXQTermString then
          result.value:=TXQTermString(children[0]).value
        else raiseEvaluationError('Invalid parameter for processing-instruction kind test: '+children[0].ToString);
        include(result.matching, qmValue) ;
      end else if select = 'element' then begin
        if not (children[0] is TXQTermNodeMatcher) then raiseEvaluationError('Invalid element test.');
        if TXQTermNodeMatcher(children[0]).select <> '*' then begin
          Include(result.matching, qmValue);
          result.value:=TXQTermNodeMatcher(children[0]).select;
          if TXQTermNodeMatcher(children[0]).hadNamespace then begin
            Include(result.matching, qmCheckNamespace);
            result.namespace:=TXQTermNodeMatcher(children[0]).namespace;
          end;
        end else if TXQTermNodeMatcher(children[0]).hadNamespace then raiseEvaluationError('Namespace:wildcard not allowed in element test') ;
      end else raiseEvaluationError('Children not allowed for element test "'+select+'"');
    exit;
  end;
  case select of
    '/': result.typ := qcDocumentRoot;
    '.': begin
      result.typ:=qcSameNode; //same node /./
      result.matching:=[qmElement, qmAttribute];
    end;
    '..': begin
      result.typ:=qcDirectParent; //parent /../
      result.matching:=[qmElement];
    end;
    '*': begin
      result.typ:=getAxis(axis); //any child /*/
      result.matching:=[qmElement,qmAttribute, qmExcludeRoot];
      if (hadNamespace) and (namespace <> '*') then begin
        Include(Result.matching, qmCheckNamespace);
        result.namespace:=namespace;
      end;
    end;
    else begin
      result.typ := getAxis(axis);
      result.matching := [qmValue,qmElement];
      result.value:=select;
      if (namespace <> '*') then begin
        Include(Result.matching, qmCheckNamespace);
        result.namespace:=namespace;
      end;
    end;
  end;
end;

{ TXQTermUnaryOp }

constructor TXQTermUnaryOp.create(const op: string; arg: TXQTerm);
begin
  index := binaryOps.IndexOf(op);
  if arg <> nil then push(arg);
end;

function TXQTermUnaryOp.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if length(children)<1 then raiseEvaluationError( 'Not enough subterms')
  else if length(children)>1 then raiseEvaluationError('Too many subterms');
  if index < 0 then raiseEvaluationError('Unknown unary op');
  result := xqvalue();
  PXQOperatorInfo(binaryOps.Objects[index])^.func(context, xqvalue(0),children[0].evaluate(context),result);
end;

{ TXQTermNumber }

constructor TXQTermNumber.create(const avalue: string);
begin
  if strContains(avalue,'e') or strContains(avalue,'E') then value := TXQValue_double.create(StrToFloat(avalue,XQFormats))
  else if strContains(avalue,'.') then value := xqvalue(StrToFloat(avalue,XQFormats))
  else value := xqvalue(StrToInt65(avalue));
end;

function TXQTermNumber.evaluate(const context: TEvaluationContext): TXQValue;
begin
  result := value.clone;
end;

destructor TXQTermNumber.destroy;
begin
  value.free;
  inherited destroy;
end;

{ TXQTermReadAttribute }

constructor TXQTermReadAttribute.create(avalue: string; func: boolean);
begin
  if func then begin
    if pos('::', avalue) > 0 then if strSplitGet('::', avalue) <> 'attribute' then raiseParsingError('Invalid axis for attribute test');
    if (avalue <> 'attribute') and (avalue <> 'node') then raiseParsingError('invalid attribute test: '+avalue);
    value := '*';
  end else begin
    if pos(':', avalue) > 0 then namespace := strSplitGet(':', avalue);
    value := avalue;
  end;
end;

function TXQTermReadAttribute.evaluate(const context: TEvaluationContext): TXQValue;
var
  tempEl: TTreeElement;
  testValue: Boolean;
  testNS: Boolean;
  readvalue: String;
  readnamespace: String;
begin
  if (context.SeqValue <> nil) and (context.SeqValue is TXQValueNode) then
    tempEl := TXQValueNode(context.SeqValue).node
   else
    tempEl:=context.ParentElement;
  if tempEl.typ = tetProcessingInstruction then
    exit(xqvalue);

  readvalue := value;
  readnamespace := namespace;
  if length(children) > 0 then begin
    if not (children[0] is TXQTermNodeMatcher) then raiseEvaluationError('Invalid subtype');
    readvalue := TXQTermNodeMatcher(children[0]).select;
    readnamespace := TXQTermNodeMatcher(children[0]).namespace;
  end;

  result := nil;
  tempEl := tempEl.attributes;
  testValue := readvalue <> '*';
  testNS := (readnamespace <> '*') and (testValue or (readnamespace <> ''));
  while tempEl <> nil do begin
    if      (not testValue or striEqual(tempEl.value, readvalue))
        and (not testNS or striEqual(tempEl.namespace, readnamespace)) then begin
      if result = nil then result := xqvalue(tempEl.reverse)
      else begin
        if not (result is TXQValueSequence) then result := TXQValueSequence.create(result);
        TXQValueSequence(result).addChild(xqvalue(tempEl.reverse))
      end
    end;
    tempEl := tempEl.next;
  end;
  if result = nil then result:=xqvalue();
end;

{ TXQTermVariable }

constructor TXQTermVariable.create(const avalue: string);
begin
  value := avalue;
  if value = '' then raiseEvaluationError('variable with empty name');
  if value[1] <> '$' then raiseEvaluationError('variable name does not start with $:  ' + value);
  delete(value,1,1);
  if value[length(value)] = ';' then delete(value, length(value), 1);
end;

function TXQTermVariable.evaluate(const context: TEvaluationContext): TXQValue;
begin
  if context.temporaryVariables <> nil then begin
    result := nil;
    if context.temporaryVariables.hasVariableOrObject(value, @result) then begin
      if result <> nil then result := result.clone
      else result := xqvalue();
      exit();
    end;
  end;
  if value = '$' then result := xqvalue('$') //default $$; as $
  else if value = 'line-ending' then result := xqvalue(LineEnding) //default $line-ending; as #13#10
  else result := xqvalue();
  if assigned(context.sender.OnEvaluateVariable) then context.sender.OnEvaluateVariable(self, value, result );
end;
{ TXQTermString }

constructor TXQTermString.create(avalue: string);
begin
  value := avalue;
end;

function TXQTermString.evaluate(const context: TEvaluationContext): TXQValue;
begin
  Result := xqvalue(value);
end;

