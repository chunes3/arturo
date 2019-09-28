/*****************************************************************
 * Arturo
 * 
 * Programming Language + Interpreter
 * (c) 2019 Yanis Zafirópulos (aka Dr.Kameleon)
 *
 * @file: parser/expressions.d
 *****************************************************************/

module parser.expressions;

// Imports

import core.memory;
import std.array;
import std.stdio;

import parser.expression;

import value;

// C Interface

extern (C) {
	void* new_Expressions() { return cast(void*)(new Expressions()); }
	void add_Expression(Expressions e, Expression ex) { GC.addRoot(cast(void*)e); e.add(ex); }
}

// Functions

class Expressions {

	Expression[] lst;

	this() {
		lst = [];
	}

	void add(Expression ex) {
		lst ~= ex;
	}

	Value evaluate(bool forceArray=false) {
		if (forceArray || lst.length > 1) {
			Value[] res;

			foreach (Expression e; lst) res ~= e.evaluate();
		
			return new Value(res);
		} 
		else return lst[0].evaluate();
	}

}