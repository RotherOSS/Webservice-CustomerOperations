.. image:: ../images/otobo-logo.png
   :align: center
|

.. toctree::
    :maxdepth: 2
    :caption: Contents

Sacrifice to Sphinx
===================

Description
===========
Provides two additional GenericInterface operations to create or update customers and customer users via web service.

``Customer::CustomerUpsert`` inserts a customer if it does not exist yet and updates it otherwise. ``Customer::CustomerUserUpsert`` does the same for customer users. Both operations accept a single entry or a list of entries per request, so that customer data from an external system can be synchronized in one call.

System requirements
===================

Framework
---------
OTOBO 11.1.x

Packages
--------
\-

Third-party software
--------------------
\-

Usage
=====

Setup
-----
After installation, the operations ``Customer::CustomerUpsert`` and ``Customer::CustomerUserUpsert`` are available in the provider configuration of any web service. Go to *Admin -> Web Services*, select or create a web service and add the desired operation via *Add Operation*. Afterwards, map the operation to a route (e.g. ``/CustomerUpsert``) in the configuration of the network transport.

Every request has to be authenticated by an agent, either with ``UserLogin`` and ``Password`` or with a valid ``SessionID``. The changes are stored in the name of this agent.

Customer::CustomerUpsert
^^^^^^^^^^^^^^^^^^^^^^^^
Creates or updates customers (customer companies). The customer data is passed in the parameter ``Customer``, either as a single object or as a list of objects.

* ``CustomerID`` and ``CustomerCompanyName`` are required.
* If a customer with the given ``CustomerID`` exists, it is updated, otherwise a new customer is created.
* To change the ``CustomerID`` of an existing customer, pass the current ID as ``CustomerCompanyID`` and the new one as ``CustomerID``. The update is rejected if the new ``CustomerID`` is already in use.
* All further fields of the customer backend (e.g. ``CustomerCompanyStreet``, ``CustomerCompanyZIP``, ``CustomerCompanyCity``, ``CustomerCompanyCountry``, ``CustomerCompanyURL``, ``CustomerCompanyComment``) are optional. ``ValidID`` defaults to 1 (valid).

.. code-block:: json

    {
        "UserLogin": "agent",
        "Password": "secret",
        "Customer": {
            "CustomerID": "example.com",
            "CustomerCompanyName": "Example Inc.",
            "CustomerCompanyCity": "Miami",
            "CustomerCompanyCountry": "USA"
        }
    }

The response contains the ``CustomerID`` of the inserted or updated customer. If a list was sent, a list of IDs is returned.

Customer::CustomerUserUpsert
^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Creates or updates customer users. The customer user data is passed in the parameter ``CustomerUser``, either as a single object or as a list of objects.

* ``UserLogin``, ``UserFirstname``, ``UserLastname`` and ``UserEmail`` are required.
* If a customer user with the given ``UserLogin`` exists, it is updated, otherwise a new customer user is created. When creating a customer user, ``UserCustomerID`` is required as well.
* To change the ``UserLogin`` of an existing customer user, pass the current login as ``ID`` and the new one as ``UserLogin``.
* ``UserPassword`` and all further fields of the customer user backend are optional. ``ValidID`` defaults to 1 (valid).

.. code-block:: json

    {
        "UserLogin": "agent",
        "Password": "secret",
        "CustomerUser": [
            {
                "UserLogin": "jdoe",
                "UserFirstname": "John",
                "UserLastname": "Doe",
                "UserEmail": "john.doe@example.com",
                "UserCustomerID": "example.com"
            }
        ]
    }

The response contains the ``UserLogin`` of the inserted or updated customer user. If a list was sent, a list of logins is returned.

.. note::

    Lists are processed in the given order. If an entry fails, processing stops and an error is returned. Entries processed before the failing one remain stored.

Configuration Reference
-----------------------

GenericInterface::Operation::ModuleRegistration
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

GenericInterface::Operation::Module###Customer::CustomerUpsert
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
GenericInterface module registration for the operation layer.

GenericInterface::Operation::Module###Customer::CustomerUserUpsert
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
GenericInterface module registration for the operation layer.

About
=======

Contact
-------
| Rother OSS GmbH
| Email: hello@otobo.io
| Web: https://otobo.io

Version
-------
Author: |doc-vendor| / Version: |doc-version| / Date of release: |doc-datestamp|
