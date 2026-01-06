# %%
class MetaOne(type):
    def __new__(cls, name, bases, dict):
        pass


class MetaTwo(type):
    def __init__(cls, name, bases, dict):
        pass
# %%
"""
 __new__(): is used when a user wants to define a dictionary of tuples before the class creation.
 it returns an instance of a class and is easy to override/manage the flow of objects.

 __init__(): is called after the object has already been created and simply initializes it.


ex:
"""
class Meta(type):
    def __init__(cls, name, base, dct):
        cls.attribute = 200


class Test(metaclass = Meta):
    pass

"""
In the official python docs, the __call__ method can be used to define a custom Metaclass.
You can override the other methods like __prepare__ when calling a class to define custom behavior.

Much like how a class behaves like a template to create objects, in the same way, Metaclass acts like a template
for the class creation. Therefore, a Metaclass is also known as a **class factory**.
"""

Test.attribute  # 200

# %%
"""
Decorator vs. Metaclass
`Decorator` is a popular feature of python which allows you to add more functionality to the code.
A decoroat is a callable object which helps modify the existing class or even a function. During compilation,
part of the code calls and modifies another part. This process is also known as metaprogramming.

Decorator:
- Returns the same class after making changes (eg. monkey-patching)
- Lacks flexibility
- Isnt compatible to perform subclassing

Metaclass:
- Used whenever a new class is created
- Provides flexbility and customization of classes
- Provides subclassing by using inheritance and converting object methods to static methods for better optimization

ex:
"""
def decor(cls):
    class NewClass(cls):
        attribute = 200
    return NewClass

    @decor
    class Test1:
        pass

    @decor
    class Test2:
        pass

        print(Test1.attribute)

        print(Test2.attribute)

# %%
## assuming an existing decorator named decorate, this code:
@decorate
def target():
    print('running target()')

# has the same effect as writing this:
def target():
    print('running target()')

target = decorate(target)
