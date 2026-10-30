// GrimoireCore has a type named Observation (a session observation). Inside this
// module that name hides the Observation framework, and @Observable expands to
// `Observation.Observable` and `Observation.ObservationRegistrar`. These aliases
// make those names resolve through the core type to the framework again.
// This file must not import GrimoireCore, so the names here are the framework's.
import Observation

typealias ObservationFrameworkObservable = Observable
typealias ObservationFrameworkRegistrar = ObservationRegistrar
