unit xquery3_1_tests;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

procedure unittests(TestErrors:boolean);


implementation

uses xquery, simplehtmltreeparser, xquery_module_math, math, commontestutils;

procedure unittests(testerrors: boolean);
var
  count: integer;
  ps: TXQueryEngine;
  xml: TTreeParser;

  function performUnitTest(s1,s2,s3: string): string;
  begin
    inc(globalTestCount);
    if s3 <> '' then xml.parseTree(s3);
    ps.parseQuery(s1, xqpmXQuery3_1);
    //ps.LastQuery.getTerm.getContextDependencies;
    result := ps.evaluate(xml.getLastTree).toString;
  end;

  procedure t(a,b: string; c: string = '');
  var
    got: String;
  begin
    try
    count+=1;
    got := performUnitTest('join('+a+')',b,c);
    if got<>b then
      raise Exception.Create('XQuery 3.1 Test failed: '+IntToStr(count)+ ': '+a+#13#10'got: "'+got+'" expected "'+b+'"');

    except on e:exception do begin
      writeln('Error @ "',a, '"');
      raise;
    end end;
  end;

{  procedure f(a, code: string; c: string = '');
   var
     err: string;
   begin
     if not TestErrors then exit;
     err := '-';
     try
     performUnitTest(a,'<error>',c);

     except on e: EXQEvaluationException do begin
       err := e.namespace.getPrefix+':'+e.errorCode;
     end; on e: EXQParsingException do begin
       err := e.namespace.getPrefix+':'+e.errorCode;
     end end;
     if err = '' then raise Exception.Create('No error => Test failed ');
     if (err <> code) and (err <> 'err:'+code) then raise Exception.Create('Wrong error, expected '+code+ ' got '+err);
   end;
 }
begin
  count:=0;
  ps := TXQueryEngine.Create;
  ps.StaticContext.baseURI := 'pseudo://test';
  ps.ImplicitTimezoneInMinutes:=-5 * 60;
  ps.ParsingOptions.AllowJSON := false;
  ps.ParsingOptions.AllowJSONLiterals:=false;
  xml := TTreeParser.Create;
  xml.readComments:=true;
  xml.readProcessingInstructions:=true;

  ps.StaticContext.strictTypeChecking := true;

  XQGlobalTrimNodes:=false;

  t('abs#1 ! (typeswitch (.) case function (anyAtomicType?) as anyAtomicType? return "T" default return "F", typeswitch (.) case function (item()) as anyAtomicType? return "T" default return "F", typeswitch (.) case function (numeric?) as anyAtomicType? return "T" default return "F" )', 'F F T');

  t('serialize(<a>xyz</a>, map {"method": "xml", "use-character-maps": map { "a": "123", "y": "foo" } })', '<a>xfooz</a>');
  t('serialize(<a>xyzä</a>, map {"method": "xml", "cdata-section-elements": QName("", "a") })', '<a><![CDATA[xyzä]]></a>');
  t('serialize(<a>]]>]]>xy]]>zä]]>]]></a>, map {"method": "xml", "cdata-section-elements": QName("", "a") })', '<a><![CDATA[]]]]><![CDATA[>]]]]><![CDATA[>xy]]]]><![CDATA[>zä]]]]><![CDATA[>]]]]><![CDATA[>]]></a>');
  t('serialize(<a>]]>]]>xy]]>zä]]>]]></a>, map {"method": "xml", "encoding": "us-ascii", "cdata-section-elements": QName("", "a") })', '<a><![CDATA[]]]]><![CDATA[>]]]]><![CDATA[>xy]]]]><![CDATA[>z]]>&#xE4;<![CDATA[]]]]><![CDATA[>]]]]><![CDATA[>]]></a>');

  writeln('XQuery 3.1: ', count, ' completed');
  ps.free;
  xml.Free;
end;

end.

