{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit internettools;

{$warn 5023 off : no warning about unused units}
interface

uses
<<<<<<< HEAD
  bbutils, extendedhtmlparser, simpleinternet, internetaccess, 
  simplehtmlparser, simplehtmltreeparser, simplexmlparser, xquery, 
  synapseinternetaccess, w32internetaccess, simplexmltreeparserfpdom, 
  xquery_json, mockinternetaccess, xquery__regex, xquery__parse, 
  xquery_module_math, xquery__functions, multipagetemplate, 
  xquery.internals.rng, LazarusPackageIntf;
=======
  bbutils, extendedhtmlparser, simpleinternet, internetaccess, simplehtmlparser, simplehtmltreeparser, simplexmlparser, xquery, 
  synapseinternetaccess, w32internetaccess, simplexmltreeparserfpdom, xquery_json, mockinternetaccess, xquery__regex, xquery__parse, 
  xquery_module_math, xquery__functions, multipagetemplate, xquery.internals.common, xquery.namespaces, 
  xquery.internals.protectionbreakers, xquery.internals.lclexcerpt, xquery.internals.rng, LazarusPackageIntf;
>>>>>>> 9dc900896b5ebad48404c5a4adb5f9d737ef12e6

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('internettools', @Register);
end.
