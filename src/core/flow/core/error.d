module flow.core.error;

import flow.util.error;

class ProcessError : FlowError {mixin error;}

class TickException : FlowException {mixin exception;}
class EntityException : FlowException {mixin exception;}
class SpaceException : FlowException {mixin exception;}
class ProcessException : FlowException {mixin exception;}
class JunctionException : FlowException {mixin exception;}