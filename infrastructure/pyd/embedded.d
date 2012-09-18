/*
Copyright (c) 2012 Ellery Newcomer

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

/// Contains utilities for embedding python in D.
///
/// Importing this module will call Py_Initialize.
module pyd.embedded;

/+
 + Things we want to do:
 +  * run python code in D (easily) [check]
 +  * run D code in python [check]
 +  * declare python functions and use them in D [check]
 +  * access and manipulate python globals in D [check]
 +  * wrap D classes/structs and use them in python or D [check]
 +  * use python class instances in D [check]
 +  * wrap D ranges and iterators or whatever and iterate through them in python [why?]
 +  * wrap python iterators as D input ranges [check]
 +  * do things with inheritance [why??!??]
 +  * do things with multithreading
 +/  

import deimos.python.Python;
import pyd.pyd;
import util.conv;
import std.algorithm: findSplit;
import std.string: strip;
import std.traits;

shared static this() {
    py_init();
}

/++
 + Fetch a python module object.
 +/
PydObject py_import(string name) {
    return new PydObject(PyImport_ImportModule(zcc(name)));
}

/++
Wraps a python function (specified as a string) as a D function roughly of
signature func_t

Params:
python = a python function 
modl = context in which to run expression. must be a python module name.
func_t = type of d function
 +/
ReturnType!func_t py_def( string python, string modl, func_t) 
    (ParameterTypeTuple!func_t args, string file = __FILE__, size_t line = __LINE__) {
    //Note that type is really the only thing that need be static here, but hey.
        alias ReturnType!func_t R;
        alias ParameterTypeTuple!func_t Args;
    enum afterdef = findSplit(python, "def")[2];
    enum ereparen = findSplit(afterdef, "(")[0];
    enum name = strip(ereparen) ~ "\0";
    static PydObject func; 
    static PythonException exc;
    static string errmsg;
    static bool once = true;
    if(once) {
        once = false;
        auto globals = py_import(modl).getdict();
        auto globals_ptr = Py_INCREF(globals.ptr);
        scope(exit) Py_DECREF(globals_ptr);
        auto locals = py((string[string]).init);
        auto locals_ptr = Py_INCREF(locals.ptr);
        scope(exit) Py_DECREF(locals_ptr);
        if("__builtins__" !in globals) {
            auto builtins = new PydObject(PyEval_GetBuiltins());
            globals["__builtins__"] = builtins;
        }
        auto pres = PyRun_String(
                    zcc(python), 
                    Py_file_input, globals_ptr, locals_ptr);
        if(pres) {
            auto res = new PydObject(pres);
            func = locals[name];
        }else{
            try{
                handle_exception();
            }catch(PythonException e) {
                exc = e;
            }
        }
    }
    if(!func) {
        throw exc;
    }
    return func(args).to_d!R();
}

/++
Evaluate a python expression once and return the result.

Params:
python = a python expression
modl = context in which to run expression. either a python module name, or "".
 +/
T py_eval(T = PydObject)(string python, string modl = "", string file = __FILE__, size_t line = __LINE__) {
    PydObject locals = null;
    PyObject* locals_ptr = null;
    if(modl == "") {
        locals = py((string[string]).init);
    }else {
        locals = py_import(modl).getdict();
    }
        locals_ptr = Py_INCREF(locals.ptr);
    if("__builtins__" !in locals) {
        auto builtins = new PydObject(PyEval_GetBuiltins());
        locals["__builtins__"] = builtins;
    }
    auto pres = PyRun_String(
            zcc(python), 
            Py_eval_input, locals_ptr, locals_ptr);
    scope(exit) Py_XDECREF(locals_ptr);
    if(pres) {
        auto res = new PydObject(pres);
        return res.to_d!T();
    }else{
        handle_exception(file,line);
        assert(0);
    }
}

/++
Evaluate one or more python statements once.

Params:
python = python statements
modl = context in which to run expression. either a python module name, or "".
 +/
void py_stmts(string python, string modl = "",string file = __FILE__, size_t line = __LINE__) {
    PydObject locals;
    PyObject* locals_ptr;
    if(modl == "") {
        locals = py((string[string]).init);
    }else {
        locals = py_import(modl).getdict();
    }
    locals_ptr = Py_INCREF(locals.ptr);
    if("__builtins__" !in locals) {
        auto builtins = new PydObject(PyEval_GetBuiltins());
        locals["__builtins__"] = builtins;
    }
    auto pres = PyRun_String(
            zcc(python), 
            Py_file_input, locals_ptr, locals_ptr);
    scope(exit) Py_DECREF(locals_ptr);
    if(pres) {
        Py_DECREF(pres);
    }else{
        handle_exception(file,line);
    }
}

