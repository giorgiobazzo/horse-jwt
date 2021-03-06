unit Horse.JWT;

interface

uses Horse, System.Classes, System.JSON, Web.HTTPApp, System.SysUtils,
  JOSE.Core.JWT, JOSE.Core.JWK, JOSE.Core.Builder,
  JOSE.Consumer.Validators, JOSE.Consumer, JOSE.Context, REST.JSON;

procedure Middleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);
function HorseJWT(ASecretJWT: string; AHeader: string = 'authorization')
  : THorseCallback; overload;
function HorseJWT(ASecretJWT: string; ASessionClass: TClass;
  AHeader: string = 'authorization'): THorseCallback; overload;

implementation

var
  SecretJWT: string;
  SessionClass: TClass;
  Header: string;

function HorseJWT(ASecretJWT: string; AHeader: string = 'authorization')
  : THorseCallback; overload;
begin
  SecretJWT := ASecretJWT;
  Header := AHeader;
  Result := Middleware;
end;

function HorseJWT(ASecretJWT: string; ASessionClass: TClass;
  AHeader: string = 'authorization'): THorseCallback; overload;
begin
  Result := HorseJWT(ASecretJWT, AHeader);
  SessionClass := ASessionClass;
end;

procedure Middleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LValidations: TJOSEConsumer;
  LJWT: TJOSEContext;
  LToken, LHeaderNormalize: string;
  LSession: TObject;
  LJSON: TJSONObject;
begin
  LHeaderNormalize := Header;
  if Length(LHeaderNormalize) > 0 then
    LHeaderNormalize[1] := UpCase(LHeaderNormalize[1]);

  LToken := Req.Headers[Header];
  if LToken.Trim.IsEmpty and
    not Req.Query.TryGetValue(Header, LToken) and
    not Req.Query.TryGetValue(LHeaderNormalize, LToken) then
  begin
    Res.Send('Token not found').Status(401);
    raise EHorseCallbackInterrupted.Create;
  end;

  if Pos('bearer', LowerCase(LToken)) = 0 then
  begin
    Res.Send('Invalid authorization type').Status(401);
    raise EHorseCallbackInterrupted.Create;
  end;

  LToken := LToken.Replace('bearer ', '', [rfIgnoreCase]);
  LValidations := TJOSEConsumerBuilder.NewConsumer.SetVerificationKey(SecretJWT)
    .SetSkipVerificationKeyValidation.SetRequireExpirationTime.Build;

  try
    LJWT := TJOSEContext.Create(LToken, TJWTClaims);
    try
      try
        LValidations.ProcessContext(LJWT);
        LJSON := LJWT.GetClaims.JSON;

        if Assigned(SessionClass) then
        begin
          LSession := SessionClass.Create;
          TJson.JsonToObject(LSession, LJSON);
        end
        else
          LSession := LJWT.GetClaims.JSON.Clone;

        THorseHackRequest(Req).SetSession(LSession);
      except
        on E: exception do
        begin
          if E.InheritsFrom(EHorseCallbackInterrupted) then
            raise EHorseCallbackInterrupted(E);
          Res.Send('Unauthorized').Status(401);
          raise EHorseCallbackInterrupted.Create;
        end;
      end;

      try
        Next();
      finally
        if Assigned(LSession) then
          LSession.Free;
      end;

    finally
      LJWT.Free;
    end;
  finally
    LValidations.Free;
  end;
end;

end.
