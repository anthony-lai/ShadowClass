Copyright 2018, Oath Inc
Licensed under the terms of the MIT license. See LICENSE file in https://github.com/anthony-lai/ShadowClass/blob/master/LICENSE for terms.

# ShadowClass

Shadow Subclass Testing was invented for the purposes of dealing with the intricacies of Swift.

By using `fileprivate` variables alongside test subclasses within the same file as the original class, Obj-c testing methods can be replicated.

The following information is accurate as of Swift 4, Xcode Version 9.0.1 (9A1004)

## One minute tutorial

1. Install SourceKitten: https://github.com/jpsim/SourceKitten
2. Run `git submodule add git@github.com:anthony-lai/ShadowClass.git ShadowClass` from your root project directory.
3. In Xcode, go to `File`->`New`->`Target`, and select `Cross-platform` at the top, then `Aggregate`.
4. Inside `Build Phases`, click the + sign to add a `New Run Script Phase`.
5. Copy paste the following inside:

```
echo "Searching for Shadow Files"
"${SRCROOT}/ShadowClass/TestClassBuilder.swift"
if [ $? != 0 ] ; then
    echo "error: SourceKit cloning failed"
    exit 1
fi
```

6. Add `"//  @ShadowTesting"` to the first line of any file you want shadowed. (Changing the value of `TestFileIdentifierLines` to some value `x` within `TestClassBuilder.swift` allows you to put it in the first `x`  lines instead. `x` is zero indexed.)
7. Change any variables you want to expose to testing from `private` to `fileprivate`.
8. Run the target you created. By default, the test subclasses will be generated and dropped into a folder called `ShadowClasses` in your root project directory ( `GenerateSwiftTestFiles = true`). You can, however, directly append the test files into your actual classes by setting `AppendToSwiftFiles = true` before you run the target.
9. Copy paste the generated subclasses into the same file as the original class.
10. Go to `Project`->`Info`->`Configurations` and use the + sign to duplicate your `Debug` build and rename it to `Testing`.
11. In `Build Settings`->`Other Swift Flags`, add `-DTESTING`.
12. From the scheme selector, `Edit Scheme` and change `Testing`'s `Build Configuration` to `Testing`.

### Recommended

1. Set up `TestClassCanary.swift` to run whenever you build your normal target. This is achieved by adding a `New Run Script Phase` to your normal target and then pasting this inside:

```
echo "Searching for test classes"
"${SRCROOT}/ShadowClass/TestClassCanary.swift"
if [ $? != 0 ] ; then
    echo "error: Found Test classes not excepted by macro flag"
    exit 1
fi
```

## Rationale

### Access control

Swift has 5 primary levels of access.

1. Private
* Only accessable from within the current enclosing context
2. Fileprivate
* Only accessable from within the defining file
3. Internal
* Only accessable from within the defining module
* Default access level
4. Public
* Accessable to the world, but only overridable and subclassable within the defining module
5. Open
* Allows for overriding and subclassing outside the defining module

Due to Swift's lack of a 'protected' access level, it is impossible to test private variables despite using `@testable import` in the test files. Test files are technically within a diferent module from the source files, and as such, `@testable import` simply exposes `internal` methods, not `private` or `fileprivate`.

### Testing metholodogy

Shadow Subclass Testing was developed with the following core principles, in order of priority.

1. Black box as much functionality as possible in the release build.
2. Test every variable that has an effect on behaviour, no matter the access level.
3. Write tests using only what an implementer would write, i.e. only use `public` and `internal` functions to manipulate state.
4. Don't ship any test code.

This led to a paradox. Due to Swift's access levels, Rule 1 and Rule 2 would heavily interfere with each other. Calculated members of a class, such as the `alpha` of a `UIView`, should often be `private`. However, since this variable has an effect on behaviour, it should be tested, despite the fact that the test module cannot access `private` variables.

`Car.swift`

```swift

class Car {

    var engine: Engine?

    func startEngine() {
        do {
            try engine?.ignite()
        } catch {
            //car issues
        }
    }
}
```

`Engine.swift`

```swift

class Engine {

    private var speed = 0

    func ignite() throws {
        do {
            try ignitePrimer()
        } catch {
            throw error
        }
    }

    private func ignitePrimer() throws {
        if success() {
            speed = 1000
        } else {
            throw IgniteError.outOfGas
        }
    }

    private func success() -> Bool {
        //return True 99% of the time
        }

}
```

The above two files are an abstracted representation of a car engine starting. The car's members and methods are set to `internal` so testing `Car.swift` is straightforward, but the engine's's privacy levels make testing difficult. Plus, it would be ideal for us to be able to ensure, for testing purposes, that an engine ignites 100% of the time. In short, we want to be able to:

1. Read values of `private` properties
2. Override `private` methods

We could do this by changing `private` to `private(set)`, and it would allow us to hide a property from another class, but it would not let us truly `private` a variable that we don't want another class to read, even if both classes are in the same module.

We can do this by changing `Engine.swift` to the following:

```swift
class Engine {

    fileprivate var speed = 0

    func ignite() throws {
        try ignitePrimer()
    }

    fileprivate func ignitePrimer() throws {
        if success() {
            speed = 1000
        } else {
            throw IgniteError.outOfGas
        }
    }

    fileprivate func success() -> Bool {
        //return True 99% of the time
    }

}

class TestEngine: Engine {

    var test_speed: Int { get { return speed } }

    override func ignitePrimer() throws {
        try super.ignitePrimer()
    }

    override func success() -> Bool {
        return true
    }
}
```

By changing `private` to `fileprivate`, and adding a test subclass that can access those variables, we enable the testing suite to read variables that will be hidden from the end user.

In order to adhere to rule 4, we can simply wrap the test class within an `#IF TESTING` `#ENDIF` macro that we define within a test target. We can observe specific variables about `TestEngine` that we could not about the original engine, and these variables would be set by only calling the functions available in `Car.swift`

The final version of `Engine.swift` thus looks like this:

```swift
class Engine {

    fileprivate var speed = 0

    func ignite() throws {
        try ignitePrimer()
    }

    fileprivate func ignitePrimer() throws {
        if success() {
            speed = 1000
        } else {
            throw FireError.misfire
        }
    }

    fileprivate func success() -> Bool {
        //return True 99% of the time
    }

}

#IF TESTING
    class TestEngine: Engine {

        var test_speed: Int { get { return speed } }

        override func ignitePrimer() throws {
            try super.ignitePrimer()
        }

        override func success() -> Bool {
            return true
        }
    }
#ENDIF
```

This pattern also helps improve code coverage. Variables now which are `private` are known to be untested simply by virtue of their access level, while `fileprivate` variables aren't.

To ensure compliance with rule 4, a simple compile-time script that scans for instances of test classes outside `#IF TESTING` macros can act as a canary, failing the build if it finds such an instance.

### Testing automation

`TestClassBuilder.swift` is designed to automate creation of Shadow Test Classes by using SourceKit. The script currently searches for all `.swift` files within the project directory, and if the file's first line is `//  @ShadowTesting`, it then searches that directory for valid classes to make a Shadow Copy of.

Valid classes are classes whose name do not begin with `"Test"`. All `fileprivate` variables and methods are scraped by the script into the new shadow class.

#### Limitations

SourceKit is incapable of realizing the type of implicit declarations, e.g., `var integer = 0` as is not parsed as an integer but `var integer: Int = 0` is.

SourceKit is incapable of finding the return type of a function. Instead, we insert editor placeholders to remind the developer to fill out appropriate function definitions.
