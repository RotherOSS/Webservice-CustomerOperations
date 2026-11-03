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
use Kernel::System::UnitTest::RegisterDriver;                                # Set up $Kernel::OM and the test driver $Self
use Kernel::GenericInterface::Debugger                                ();
use Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert ();
use Kernel::GenericInterface::Operation::Session::SessionCreate       ();    ## no perlimports, CreateSessionID()

our $Self;

my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

# disable SessionCheckRemoteIP setting
$ConfigObject->Set(
    Key   => 'SessionCheckRemoteIP',
    Value => 0,
);

# test email addresses use example.com, which has no MX record
$ConfigObject->Set(
    Key   => 'CheckEmailAddresses',
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

my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

# customer company the customer users belong to
my $CustomerID = 'company-' . $RandomID;
ok(
    $Kernel::OM->Get('Kernel::System::CustomerCompany')->CustomerCompanyAdd(
        CustomerID          => $CustomerID,
        CustomerCompanyName => "Company $RandomID",
        ValidID             => 1,
        UserID              => 1,
    ),
    'customer company added',
);

# create a web service
my $WebserviceID = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceAdd(
    Name   => 'CustomerUserUpsert-Test-' . $RandomID,
    Config => {
        Debugger => {
            DebugThreshold => 'debug',
        },
        Provider => {
            Transport => {
                Type => '',
            },
            Operation => {
                CustomerUserUpsert => {
                    Type => 'Customer::CustomerUserUpsert',
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
    return Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert->new(
        DebuggerObject => $DebuggerObject,
        WebserviceID   => $WebserviceID,
    );
};

# helper for building a valid customer user
my $CustomerUserData = sub {
    my ( $Login, %Param ) = @_;

    return {
        UserLogin      => $Login,
        UserFirstname  => 'Test',
        UserLastname   => 'Customer',
        UserEmail      => "$Login\@example.com",
        UserCustomerID => $CustomerID,
        %Param,
    };
};

my %Auth = (
    UserLogin => $UserLogin,
    Password  => $Password,
);

subtest 'new()' => sub {
    my $Missing = Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert->new(
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

    $Missing = Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert->new(
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

    isa_ok( $NewOperation->(), 'Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert' );
};

# requests that are rejected before any customer user is touched
my @ErrorTests = (
    {
        Name      => 'invalid web service',
        Operation => sub {
            Kernel::GenericInterface::Operation::Customer::CustomerUserUpsert->new(
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
        ErrorCode => 'CustomerUserUpsert.MissingParameter',
        ErrorLike => qr{UserLogin or SessionID is required},
    },
    {
        Name => 'UserLogin without Password',
        Data => {
            UserLogin => $UserLogin,
        },
        ErrorCode => 'CustomerUserUpsert.MissingParameter',
        ErrorLike => qr{Password or SessionID is required},
    },
    {
        Name => 'wrong password',
        Data => {
            UserLogin    => $UserLogin,
            Password     => 'wrong-' . $RandomID,
            CustomerUser => $CustomerUserData->( 'auth-fail-' . $RandomID ),
        },
        ErrorCode => 'CustomerUserUpsert.AuthFail',
    },
    {
        Name => 'invalid SessionID',
        Data => {
            SessionID    => 'invalid-' . $RandomID,
            CustomerUser => $CustomerUserData->( 'auth-fail-' . $RandomID ),
        },
        ErrorCode => 'CustomerUserUpsert.AuthFail',
    },
    {
        Name      => 'missing CustomerUser',
        Data      => {%Auth},
        ErrorCode => 'CustomerUserUpsert.MissingParameter',
        ErrorLike => qr{CustomerUser parameter is missing},
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

        my %User = $CustomerUserObject->CustomerUserDataGet( User => 'auth-fail-' . $RandomID );
        ok( !%User, 'no customer user was created' );
    };
}

# validation of single customer user entries
for my $Needed (qw(UserFirstname UserLastname UserLogin UserEmail)) {
    subtest "CustomerUser without $Needed" => sub {
        my $Login        = 'missing-' . lc($Needed) . '-' . $RandomID;
        my $CustomerUser = $CustomerUserData->($Login);
        delete $CustomerUser->{$Needed};

        my $Result = $NewOperation->()->Run(
            Data => {
                %Auth,
                CustomerUser => $CustomerUser,
            },
        );

        is( $Result->{Success},                    0,                                     'Success' );
        is( $Result->{Data}->{Error}->{ErrorCode}, 'CustomerUserUpsert.MissingParameter', 'ErrorCode' );
        like( $Result->{Data}->{Error}->{ErrorMessage}, qr{CustomerUser->$Needed parameter is missing}, 'ErrorMessage' );

        my %User = $CustomerUserObject->CustomerUserDataGet( User => $Login );
        ok( !%User, 'no customer user was created' );
    };
}

subtest 'insert without UserCustomerID' => sub {
    my $Login        = 'no-customerid-' . $RandomID;
    my $CustomerUser = $CustomerUserData->($Login);
    delete $CustomerUser->{UserCustomerID};

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => $CustomerUser,
        },
    );

    is( $Result->{Success},                    0,                                     'Success' );
    is( $Result->{Data}->{Error}->{ErrorCode}, 'CustomerUserUpsert.MissingParameter', 'ErrorCode' );
    like( $Result->{Data}->{Error}->{ErrorMessage}, qr{UserCustomerID parameter is missing}, 'ErrorMessage' );

    my %User = $CustomerUserObject->CustomerUserDataGet( User => $Login );
    ok( !%User, 'no customer user was created' );
};

my $Login = 'single-' . $RandomID;

subtest 'insert single customer user' => sub {
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => {
                UserLogin      => "  $Login ",
                UserFirstname  => ' Test ',
                UserLastname   => 'Customer',
                UserEmail      => "$Login\@example.com",
                UserCustomerID => $CustomerID,
                UserPassword   => 'some-pass',
            },
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                UserLogin => $Login,
            },
        },
        'single input returns scalar UserLogin',
    );

    my %User = $CustomerUserObject->CustomerUserDataGet( User => $Login );
    is( $User{UserLogin},      $Login,                'leading and trailing spaces removed from UserLogin' );
    is( $User{UserFirstname},  'Test',                'leading and trailing spaces removed from first name' );
    is( $User{UserEmail},      "$Login\@example.com", 'email stored' );
    is( $User{UserCustomerID}, $CustomerID,           'UserCustomerID stored' );
    is( $User{ValidID},        1,                     'ValidID defaults to 1' );
};

subtest 'update existing customer user' => sub {
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => $CustomerUserData->(
                $Login,
                UserFirstname => 'Updated',
                ValidID       => 2,
            ),
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                UserLogin => $Login,
            },
        },
        'update returns UserLogin',
    );

    my %User = $CustomerUserObject->CustomerUserDataGet( User => $Login );
    is( $User{UserFirstname}, 'Updated', 'first name updated' );
    is( $User{ValidID},       2,         'ValidID updated' );
};

subtest 'update existing customer user without UserCustomerID' => sub {
    my $CustomerUser = $CustomerUserData->(
        $Login,
        UserFirstname => 'Updated Again',
    );
    delete $CustomerUser->{UserCustomerID};

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => $CustomerUser,
        },
    );

    my %User = $CustomerUserObject->CustomerUserDataGet( User => $Login );

    is( $Result->{Success},    1,               'UserCustomerID is only required on insert' );
    is( $User{UserFirstname},  'Updated Again', 'first name updated' );
    is( $User{UserCustomerID}, $CustomerID,     'UserCustomerID is unchanged' );
};

my $RenamedLogin = 'renamed-' . $RandomID;

subtest 'rename customer user via ID' => sub {
    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => $CustomerUserData->(
                $RenamedLogin,
                ID => $Login,
            ),
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                UserLogin => $RenamedLogin,
            },
        },
        'rename returns the new UserLogin',
    );

    my %Old = $CustomerUserObject->CustomerUserDataGet( User => $Login );
    ok( !%Old, 'old UserLogin is gone' );

    my %New = $CustomerUserObject->CustomerUserDataGet( User => $RenamedLogin );
    is( $New{UserEmail}, "$RenamedLogin\@example.com", 'customer user available under new UserLogin' );
};

subtest 'rename onto an already existing UserLogin' => sub {
    my $ExistingLogin = 'existing-' . $RandomID;
    my $SourceLogin   = 'source-' . $RandomID;

    for my $NewLogin ( $ExistingLogin, $SourceLogin ) {
        ok(
            $CustomerUserObject->CustomerUserAdd(
                $CustomerUserData->( $NewLogin, UserFirstname => "First $NewLogin" )->%*,
                Source  => 'CustomerUser',
                ValidID => 1,
                UserID  => 1,
            ),
            "created customer user $NewLogin",
        );
    }

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => $CustomerUserData->(
                $ExistingLogin,
                ID            => $SourceLogin,
                UserFirstname => 'Clash',
            ),
        },
    );

    is( $Result->{Success},      0,                                                  'rename is rejected' );
    is( $Result->{ErrorMessage}, qq{Customer user "$ExistingLogin" already exists.}, 'ErrorMessage' );

    my %Existing = $CustomerUserObject->CustomerUserDataGet( User => $ExistingLogin );
    is( $Existing{UserFirstname}, "First $ExistingLogin", 'existing customer user is untouched' );

    my %Source = $CustomerUserObject->CustomerUserDataGet( User => $SourceLogin );
    is( $Source{UserFirstname}, "First $SourceLogin", 'source customer user is untouched' );
};

subtest 'unknown ID falls back to insert' => sub {
    my $NewLogin = 'fallback-' . $RandomID;
    my $Result   = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => $CustomerUserData->(
                $NewLogin,
                ID => 'does-not-exist-' . $RandomID,
            ),
        },
    );

    is( $Result->{Success},           1,         'Success' );
    is( $Result->{Data}->{UserLogin}, $NewLogin, 'new UserLogin returned' );

    my %User = $CustomerUserObject->CustomerUserDataGet( User => $NewLogin );
    is( $User{UserLogin}, $NewLogin, 'customer user inserted' );
};

subtest 'list of customer users' => sub {
    my @Logins = map { "list-$_-" . $RandomID } 1 .. 3;

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => [ map { $CustomerUserData->($_) } @Logins ],
        },
    );

    is(
        $Result,
        {
            Success => 1,
            Data    => {
                UserLogin => \@Logins,
            },
        },
        'list input returns array of UserLogins in input order',
    );

    for my $ListLogin (@Logins) {
        my %User = $CustomerUserObject->CustomerUserDataGet( User => $ListLogin );
        is( $User{UserLogin}, $ListLogin, "customer user $ListLogin stored" );
    }
};

subtest 'list with one entry stays a list' => sub {
    my $ListLogin = 'onelist-' . $RandomID;
    my $Result    = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => [ $CustomerUserData->($ListLogin) ],
        },
    );

    is( $Result->{Data}->{UserLogin}, [$ListLogin], 'array input with one element returns an array' );
};

subtest 'list with an invalid entry stops processing' => sub {
    my $FirstLogin = 'partial-1-' . $RandomID;
    my $ThirdLogin = 'partial-3-' . $RandomID;

    my $Invalid = $CustomerUserData->( 'partial-2-' . $RandomID );
    delete $Invalid->{UserEmail};

    my $Result = $NewOperation->()->Run(
        Data => {
            %Auth,
            CustomerUser => [
                $CustomerUserData->($FirstLogin),
                $Invalid,
                $CustomerUserData->($ThirdLogin),
            ],
        },
    );

    is( $Result->{Success},                    0,                                     'Success' );
    is( $Result->{Data}->{UserLogin},          [$FirstLogin],                         'already upserted customer users are returned' );
    is( $Result->{Data}->{Error}->{ErrorCode}, 'CustomerUserUpsert.MissingParameter', 'ErrorCode' );

    my %Third = $CustomerUserObject->CustomerUserDataGet( User => $ThirdLogin );
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

    my $SessionLogin = 'session-' . $RandomID;
    my $Result       = $NewOperation->()->Run(
        Data => {
            SessionID    => $SessionID,
            CustomerUser => $CustomerUserData->($SessionLogin),
        },
    );

    is( $Result->{Success},           1,             'Success' );
    is( $Result->{Data}->{UserLogin}, $SessionLogin, 'UserLogin returned' );
};

done_testing();
