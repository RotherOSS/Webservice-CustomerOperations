# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This program is free software: you can redistribute it and/or modify it under
# the terms of the GNU General Public License as published by the Free Software
# Foundation, either version 3 of the License, or (at your option) any later version.
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
# FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
# You should have received a copy of the GNU General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
# --

use strict;
use warnings;
use utf8;

# core modules

# CPAN modules
use Test2::V0;

# OTOBO modules
use Kernel::System::UnitTest::RegisterDriver;                            # Set up $Kernel::OM and the test driver $Self
use Kernel::GenericInterface::Debugger                            ();
use Kernel::GenericInterface::Operation::Customer::CustomerUpsert ();
use Kernel::GenericInterface::Operation::Session::SessionCreate   ();    ## no perlimports, CreateSessionID()

our $Self;

# disable SessionCheckRemoteIP setting
$Kernel::OM->Get('Kernel::Config')->Set(
    Key   => 'SessionCheckRemoteIP',
    Value => 0,
);

$Kernel::OM->ObjectParamAdd(
    'Kernel::System::UnitTest::Helper' => {
        RestoreDatabase => 1,
    },
);
my $Helper = $Kernel::OM->Get('Kernel::System::UnitTest::Helper');

my $RandomID = $Helper->GetRandomID();

my $UserLogin = $Helper->TestUserCreate(
    Groups => ['users'],
);
my $Password = $UserLogin;

my $CustomerCompanyObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

# create a web service
my $WebserviceID = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceAdd(
    Name   => 'CustomerUpsert-Test-' . $RandomID,
    Config => {
        Debugger => {
            DebugThreshold => 'debug',
        },
        Provider => {
            Transport => {
                Type => '',
            },
            Operation => {
                CustomerUpsert => {
                    Type => 'Customer::CustomerUpsert',
                },
            },
        },
    },
    ValidID => 1,
    UserID  => 1,
);
ok( $WebserviceID, 'web service added' );

my $DebuggerObject = Kernel::GenericInterface::Debugger->new(
    DebuggerConfig => {
        DebugThreshold => 'debug',
        TestMode       => 1,
    },
    WebserviceID      => $WebserviceID,
    CommunicationType => 'Provider',
);
isa_ok( $DebuggerObject, 'Kernel::GenericInterface::Debugger' );

# helper for creating a fresh operation object
my $NewOperation = sub {
    my %Param = @_;

    return Kernel::GenericInterface::Operation::Customer::CustomerUpsert->new(
        DebuggerObject => $DebuggerObject,
        WebserviceID   => $WebserviceID,
        %Param,
    );
};

my %Auth = (
    UserLogin => $UserLogin,
    Password  => $Password,
);

subtest 'new()' => sub {
    my $Missing = Kernel::GenericInterface::Operation::Customer::CustomerUpsert->new(
        WebserviceID => $WebserviceID,
    );
    is(
        $Missing,
        {
            Success      => 0,
            ErrorMessage => 'Got no DebuggerObject!',
        },
        'missing DebuggerObject',
    );

    $Missing = Kernel::GenericInterface::Operation::Customer::CustomerUpsert->new(
        DebuggerObject => $DebuggerObject,
    );
    is(
        $Missing,
        {
            Success      => 0,
            ErrorMessage => 'Got no WebserviceID!',
        },
        'missing WebserviceID',
    );

    isa_ok( $NewOperation->(), 'Kernel::GenericInterface::Operation::Customer::CustomerUpsert' );
};

# requests that are rejected before any customer is touched
my @ErrorTests = (
    {
        Name      => 'invalid web service',
        Operation => sub {
            Kernel::GenericInterface::Operation::Customer::CustomerUpsert->new(
                DebuggerObject => $DebuggerObject,
                WebserviceID   => -1,
            );
        },
        Data      => {%Auth},
        ErrorCode => 'Webservice.InvalidConfiguration',
    },
    {
        Name      => 'no authentication data',
        Data      => {},
        ErrorCode => 'CustomerUpsert.MissingParameter',
        ErrorLike => qr{UserLogin or SessionID is required},
    },
    {
        Name => 'UserLogin without Password',
        Data => {
            UserLogin => $UserLogin,
        },
        ErrorCode => 'CustomerUpsert.MissingParameter',
        ErrorLike => qr{Password or SessionID is required},
    },
    {
        Name => 'wrong password',
        Data => {
            UserLogin => $UserLogin,
            Password  => 'wrong-' . $RandomID,
            Customer  => {
                CustomerID          => 'auth-fail-' . $RandomID,
                CustomerCompanyName => 'Auth Fail',
            },
        },
        ErrorCode => 'CustomerUpsert.AuthFail',
    },
    {
        Name => 'invalid SessionID',
        Data => {
            SessionID => 'invalid-' . $RandomID,
            Customer  => {
                CustomerID          => 'auth-fail-' . $RandomID,
                CustomerCompanyName => 'Auth Fail',
            },
        },
        ErrorCode => 'CustomerUpsert.AuthFail',
    },
    {
        Name      => 'missing Customer',
        Data      => {%Auth},
        ErrorCode => 'CustomerUpsert.MissingParameter',
        ErrorLike => qr{Customer parameter is missing},
    },
);

for my $Test (@ErrorTests) {
    subtest $Test->{Name} => sub {
        my $Operation = $Test->{Operation} ? $Test->{Operation}->() : $NewOperation->();
        my $Result    = $Operation->Run( Data => $Test->{Data} );

        is( $Result->{Success},                    1,                  'ReturnError() convention: Success => 1' );
        is( $Result->{Data}->{Error}->{ErrorCode}, $Test->{ErrorCode}, 'ErrorCode' );
        if ( $Test->{ErrorLike} ) {
            like( $Result->{Data}->{Error}->{ErrorMessage}, $Test->{ErrorLike}, 'ErrorMessage' );
        }
    };
}

# validation of single customer entries
for my $Needed (qw(CustomerID CustomerCompanyName)) {
    subtest "Customer without $Needed" => sub {
        my %Customer = (
            CustomerID          => 'missing-' . $RandomID,
            CustomerCompanyName => 'Missing Inc.',
        );
        delete $Customer{$Needed};

        my $Result = $NewOperation->()->Run(
            Data => {
                %Auth,
                Customer => \%Customer,
            },
        );

        is( $Result->{Success},                    0,                                 'Success' );
        is( $Result->{Data}->{Error}->{ErrorCode}, 'CustomerUpsert.MissingParameter', 'ErrorCode' );
        like( $Result->{Data}->{Error}->{ErrorMessage}, qr{Customer->$Needed parameter is missing}, 'ErrorMessage' );

        my %Company = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => 'missing-' . $RandomID );
        ok( !%Company, 'no customer was created' );
    };
}

my $CustomerID = 'single-' . $RandomID;

subtest 'insert single customer' => sub {
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => {
                CustomerID             => "  $CustomerID  ",
                CustomerCompanyName    => ' Test Inc. ',
                CustomerCompanyStreet  => '5201 Blue Lagoon Drive',
                CustomerCompanyZIP     => '33126',
                CustomerCompanyCity    => 'Miami',
                CustomerCompanyCountry => 'USA',
                CustomerCompanyURL     => 'http://example.com',
                CustomerCompanyComment => 'some comment',
            },
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                CustomerID => $CustomerID,
            },
        },
        'single input returns scalar CustomerID',
    );

    my %Company = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $CustomerID );
    is( $Company{CustomerID},          $CustomerID, 'leading and trailing spaces removed from CustomerID' );
    is( $Company{CustomerCompanyName}, 'Test Inc.', 'leading and trailing spaces removed from name' );
    is( $Company{CustomerCompanyCity}, 'Miami',     'city stored' );
    is( $Company{CustomerCompanyZIP},  '33126',     'ZIP stored' );
    is( $Company{ValidID},             1,           'ValidID defaults to 1' );
};

subtest 'update existing customer' => sub {
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => {
                CustomerID          => $CustomerID,
                CustomerCompanyName => 'Test Inc. updated',
                CustomerCompanyZIP  => '12345',
                ValidID             => 2,
            },
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                CustomerID => $CustomerID,
            },
        },
        'update returns CustomerID',
    );

    my %Company = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $CustomerID );
    is( $Company{CustomerCompanyName}, 'Test Inc. updated', 'name updated' );
    is( $Company{CustomerCompanyZIP},  '12345',             'ZIP updated' );
    is( $Company{ValidID},             2,                   'ValidID updated' );
};

my $RenamedCustomerID = 'renamed-' . $RandomID;

subtest 'rename customer via CustomerCompanyID' => sub {
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => {
                CustomerID          => $RenamedCustomerID,
                CustomerCompanyID   => $CustomerID,
                CustomerCompanyName => 'Renamed Inc.',
            },
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                CustomerID => $RenamedCustomerID,
            },
        },
        'rename returns the new CustomerID',
    );

    my %Old = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $CustomerID );
    ok( !%Old, 'old CustomerID is gone' );

    my %New = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $RenamedCustomerID );
    is( $New{CustomerCompanyName}, 'Renamed Inc.', 'customer available under new CustomerID' );
};

subtest 'unknown CustomerCompanyID falls back to insert' => sub {
    my $NewID  = 'fallback-' . $RandomID;
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => {
                CustomerID          => $NewID,
                CustomerCompanyID   => 'does-not-exist-' . $RandomID,
                CustomerCompanyName => 'Fallback Inc.',
            },
        },
    );

    is( $Result->{Success},            1,      'Success' );
    is( $Result->{Data}->{CustomerID}, $NewID, 'new CustomerID returned' );

    my %Company = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $NewID );
    is( $Company{CustomerCompanyName}, 'Fallback Inc.', 'customer inserted' );
};

subtest 'rename onto an already existing CustomerID' => sub {
    my $ExistingID = 'existing-' . $RandomID;
    my $SourceID   = 'source-' . $RandomID;

    for my $ID ( $ExistingID, $SourceID ) {
        ok(
            $CustomerCompanyObject->CustomerCompanyAdd(
                CustomerID          => $ID,
                CustomerCompanyName => "Company $ID",
                ValidID             => 1,
                UserID              => 1,
            ),
            "created customer $ID",
        );
    }

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => {
                CustomerID          => $ExistingID,
                CustomerCompanyID   => $SourceID,
                CustomerCompanyName => 'Clash Inc.',
            },
        },
    );

    is( $Result->{Success}, 0, 'rename is rejected' );

    my %Existing = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $ExistingID );
    is( $Existing{CustomerCompanyName}, "Company $ExistingID", 'existing customer is untouched' );

    my %Source = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $SourceID );
    is( $Source{CustomerCompanyName}, "Company $SourceID", 'source customer is untouched' );

    is( $Result->{ErrorMessage}, qq{Customer "$ExistingID" already exists.}, 'ErrorMessage' );
};

subtest 'list of customers' => sub {
    my @IDs = map { "list-$_-" . $RandomID } 1 .. 3;

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => [
                map {
                    {
                        CustomerID          => $_,
                        CustomerCompanyName => "Company $_",
                    }
                } @IDs
            ],
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                CustomerID => \@IDs,
            },
        },
        'list input returns array of CustomerIDs in input order',
    );

    for my $ID (@IDs) {
        my %Company = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $ID );
        is( $Company{CustomerCompanyName}, "Company $ID", "customer $ID stored" );
    }
};

subtest 'list with one entry stays a list' => sub {
    my $ID     = 'onelist-' . $RandomID;
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => [
                {
                    CustomerID          => $ID,
                    CustomerCompanyName => 'One List Inc.',
                },
            ],
        },
    );

    is( $Result->{Data}->{CustomerID}, [$ID], 'array input with one element returns an array' );
};

subtest 'list with an invalid entry stops processing' => sub {
    my $FirstID = 'partial-1-' . $RandomID;
    my $ThirdID = 'partial-3-' . $RandomID;

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            Customer => [
                {
                    CustomerID          => $FirstID,
                    CustomerCompanyName => 'Partial One',
                },
                {
                    CustomerID => 'partial-2-' . $RandomID,
                },
                {
                    CustomerID          => $ThirdID,
                    CustomerCompanyName => 'Partial Three',
                },
            ],
        },
    );

    is( $Result->{Success},                    0,                                 'Success' );
    is( $Result->{Data}->{CustomerID},         [$FirstID],                        'already upserted customers are returned' );
    is( $Result->{Data}->{Error}->{ErrorCode}, 'CustomerUpsert.MissingParameter', 'ErrorCode' );

    my %Third = $CustomerCompanyObject->CustomerCompanyGet( CustomerID => $ThirdID );
    ok( !%Third, 'entries after the invalid one are not processed' );
};

subtest 'authentication via SessionID' => sub {
    my $SessionID = Kernel::GenericInterface::Operation::Session::SessionCreate->new(
        DebuggerObject => $DebuggerObject,
        WebserviceID   => $WebserviceID,
    )->CreateSessionID(
        Data => {%Auth},
    );
    ok( $SessionID, 'agent session created' );

    my $ID     = 'session-' . $RandomID;
    my $Result = $NewOperation->()->Run(
        Data => {
            SessionID => $SessionID,
            Customer  => {
                CustomerID          => $ID,
                CustomerCompanyName => 'Session Inc.',
            },
        },
    );

    is( $Result->{Success},            1,   'Success' );
    is( $Result->{Data}->{CustomerID}, $ID, 'CustomerID returned' );
};

done_testing();
