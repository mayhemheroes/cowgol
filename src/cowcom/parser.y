%token ASM ASSIGN BREAK CLOSEPAREN CLOSESQ.
%token COLON CONST DOT ELSE END EXTERN.
%token IF LOOP MINUS NOT OPENPAREN OPENSQ.
%token PERCENT PLUS RECORD RETURN SEMICOLON SLASH STAR.
%token SUB THEN TILDE VAR WHILE TYPE.
%token OPENBR CLOSEBR ID NUMBER AT BYTESOF ELSEIF.
%token INT TYPEDEF SIZEOF STRING.

%left COMMA.
%left AND.
%left OR.
%left PIPE.
%left CARET.
%left AMPERSAND.
%nonassoc LTOP LEOP GTOP GEOP EQOP NEOP.
%left LSHIFT RSHIFT.
%left PLUS MINUS.
%left STAR SLASH PERCENT.
%left AS.
%right NOT TILDE.

%token_type {[Token]}

%syntax_error
{
	StartError();
	print("unexpected ");
	print(yyTokenName[yymajor]);
	EndError();
}

%stack_overflow
{
	StartError();
	print("parser stack overflow");
	EndError();
}

%token_destructor
{
	if $$ != (0 as [Token]) then
		Free($$.string as [uint8]);
		Free($$ as [uint8]);
	end if;
}

program ::= statements.

statements ::= /* empty */.
statements ::= statements statement.

/* --- Top-level statements ---------------------------------------------- */

statement ::= SEMICOLON.

/* --- Simple statements ------------------------------------------------- */

statement ::= RETURN SEMICOLON.
{
	Generate(MidReturn());
}

/* --- Variable declaration ---------------------------------------------- */

statement ::= VAR newid(S) COLON typeref(T) SEMICOLON.
{
	S.kind := VAR;
	InitVariable(S, T);
}

statement ::= VAR newid(S) COLON typeref(T) ASSIGN expression(E) SEMICOLON.
{
	S.kind := VAR;
	InitVariable(S, T);
    CheckExpressionType(E, S.vardata.type);

    Generate(MidStore(E.type.typedata.width as uint8, E, MidAddress(S, 0)));
}

statement ::= VAR newid(S) ASSIGN expression(E) SEMICOLON.
{
#	if (E.type == (0 as [Symbol]))
#		SimpleError("types cannot be inferred for numeric constants");
#	if (!is_scalar(E->type))
#		SimpleError("you can only assign to lvalues");
#	S.kind := VAR;
#	init_var(S, E.type);
#	check_expression_type(&E.type, E.type);
#
#	Generate(mid_store(E.type.typesym.width, E, mid_address(S, 0)));
}

/* --- Expressions ------------------------------------------------------- */

%type expression {[Node]}
expression(E) ::= NUMBER(T).                               { E := MidConstant(T.number); }
expression(E) ::= OPENPAREN expression(E1) CLOSEPAREN.     { E := E1; }
expression(E) ::= MINUS expression(E1).                    { E := ExprNeg(E1); }
expression(E) ::= expression(E1) PLUS expression(E2).      { E := ExprAdd(E1, E2); }
expression(E) ::= expression(E1) MINUS expression(E2).     { E := ExprSub(E1, E2); }
expression(E) ::= expression(E1) STAR expression(E2).      { E := ExprMul(E1, E2); }
expression(E) ::= expression(E1) SLASH expression(E2).     { E := ExprDiv(E1, E2); }
expression(E) ::= expression(E1) PERCENT expression(E2).   { E := ExprRem(E1, E2); }
expression(E) ::= expression(E1) CARET expression(E2).     { E := ExprEor(E1, E2); }
expression(E) ::= expression(E1) AMPERSAND expression(E2). { E := ExprAnd(E1, E2); }
expression(E) ::= expression(E1) PIPE expression(E2).      { E := ExprOr(E1, E2); }
expression(E) ::= expression(E1) LSHIFT expression(E2).    { E := ExprLShift(E1, E2); }
expression(E) ::= expression(E1) RSHIFT expression(E2).    { E := ExprRShift(E1, E2); }

expression(E) ::= lvalue(E1).
{
	if E1.type != (0 as [Symbol]) then
		var dereftype := E1.type.typedata.element;
		if IsScalar(dereftype) == 0 then
			SimpleError("non-scalars cannot be used in this context");
		end if;
		E := MidLoad(dereftype.typedata.width as uint8, E1);
		E.type := dereftype;
	else
		E := E1;
	end if;
}

/* --- Lvalues ----------------------------------------------------------- */

%type lvalue {[Node]}
lvalue(E) ::= oldid(S).
{
	case S.kind is
		when CONST:
			E := MidConstant(S.constant);

		when VAR:
			E := MidAddress(S, 0);
			E.type := MakePointerType(S.vardata.type);

		when else:
			StartError();
			print(S.name);
			print(" is not a value");
			EndError();
	end case;
}

%type cvalue {Arith}
cvalue(C) ::= expression(E).
{
	if E.type != (0 as [Symbol]) then
		SimpleError("only constant values are allowed here");
	end if;
	C := E.constant.value;
}

/* --- Types ------------------------------------------------------------- */

%type typeref {[Symbol]}
typeref(S) ::= INT OPENPAREN cvalue(MIN) COMMA cvalue(MAX) CLOSEPAREN.
{
	if MAX <= MIN then
		SimpleError("invalid integer type range");
	end if;
	S := ArchGuessIntType(MIN, MAX);
}

typeref(S) ::= eitherid(ID).
{
	var sym := ID;
	if sym.kind == 0 then
		# Create a partial type.
		sym.kind := TYPE;
		sym.typedata.kind := TYPE_PARTIAL;
	end if;
	if sym.kind != TYPE then
		StartError();
		print("expected ");
		print(sym.name);
		print(" to be a type");
		EndError();
	end if;
	S := sym;
}

statement ::= TYPEDEF ID(X) ASSIGN typeref(T) SEMICOLON.
{
	var sym := AddAlias(0 as [Namespace], X, T);
}

/* --- Symbols ----------------------------------------------------------- */

%type newid {[Symbol]}
newid(S) ::= ID(T).
{
	S := AddSymbol(0 as [Namespace], T);
}

%type oldid {[Symbol]}
oldid(S) ::= ID(T).
{
	var name := T.string;
	var sym := LookupSymbol(0 as [Namespace], name);
	if sym == (0 as [Symbol]) then
		StartError();
		print("symbol '");
		print(name);
		print("' not found");
		EndError();
	end if;
	S := sym;
}

%type eitherid {[Symbol]}
eitherid(S) ::= ID(T).
{
	var sym := LookupSymbol(0 as [Namespace], T.string);
	if sym == (0 as [Symbol]) then
		sym := AddSymbol(0 as [Namespace], T);
	end if;
	S := sym;
}

