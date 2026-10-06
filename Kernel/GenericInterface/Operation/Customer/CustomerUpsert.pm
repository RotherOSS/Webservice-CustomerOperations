# --
# Copyright (C) 2018 Perl-Services.de, http://perl-services.de
# Copyright (C) 2019-2026 Rother OSS GmbH, https://otobo.io/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::GenericInterface::Operation::Customer::CustomerUpsert;

use v5.24;
use strict;
use warnings;

use parent qw(
    Kernel::GenericInterface::Operation::Common
    Kernel::GenericInterface::Operation::Customer::Common
);

# core modules

# CPAN modules

# OTOBO modules
use Kernel::System::VariableCheck qw(IsArrayRefWithData IsHashRefWithData IsString IsStringWithData);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Customer::CustomerUpsert - GenericInterface Customer CustomerUpsert Operation backend

=head1 PUBLIC INTERFACE

=head2 new()

usually, you want to create an instance of this
by using Kernel::GenericInterface::Operation->new();

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for my $Needed (qw( DebuggerObject WebserviceID )) {
        if ( !$Param{$Needed} ) {
            return {
                Success      => 0,
                ErrorMessage => "Got no $Needed!"
            };
        }

        $Self->{$Needed} = $Param{$Needed};
    }

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get('GenericInterface::Operation::CustomerUpsert');

    return $Self;
}

=head2 Run()

perform CustomerUpsert Operation. This function is able to accept
one or more customer entries in one call and returns successfully
inserted or updated customer IDs.

    my $Result = $OperationObject->Run(
        Data => {
            UserLogin => 'some agent login',                            # UserLogin or SessionID is required
            SessionID => 123,
            Password  => 'some password',                               # if UserLogin is sent then Password is required

            Customer => {                                               # Single customer or customer list is required
                CustomerID              => 'test.com',
                CustomerCompanyID       => 'oldtest.com',               # required for CustomerID-update (if no such customer
                                                                        # exists, this will be ignored by the default mapping
                                                                        # and instead a new customer via CustomerID is inserted)
                CustomerCompanyName     => 'Test Inc.',
                CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
                CustomerCompanyZIP      => '33126',
                CustomerCompanyLocation => 'Miami',
                CustomerCompanyCountry  => 'USA',
                CustomerCompanyURL      => 'http://example.com',
                CustomerCompanyComment  => 'some comment',
                ValidID                 => 1,
            },
            Customer => [
                {
                    CustomerID          => 'test.com',
                    CustomerCompanyID   => 'oldtest.com',
                    CustomerCompanyName => 'Test Inc.',
                    CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
                    CustomerCompanyZIP      => '33126',
                    CustomerCompanyLocation => 'Miami',
                    CustomerCompanyCountry  => 'USA',
                    CustomerCompanyURL      => 'http://example.com',
                    CustomerCompanyComment  => 'some comment',
                    ValidID                 => 1,
                },
                {
                    # . . .
                },
            ],
        },
    );

    $Result = {
        Success         => 1,                                  # 0 or 1
        ErrorMessage    => '',                                 # in case of error
        Data            => {                                   # result data payload after Operation
            Customer => [                                      # includes all customers that
                                                               # have been successfully upserted
                {
                    CustomerID    => 123,
                },
                {
                    # . . .
                }
            ],
            Error => {                                         # should not return errors
                ErrorCode    => 'Customer.Upsert.ErrorCode'
                ErrorMessage => 'Error Description'
            },
        },
    };

=cut

sub Run {
    my ( $Self, %Param ) = @_;

    my $Result = $Self->Init(
        WebserviceID => $Self->{WebserviceID},
    );

    if ( !$Result->{Success} ) {
        return $Self->ReturnError(
            ErrorCode    => 'Webservice.InvalidConfiguration',
            ErrorMessage => $Result->{ErrorMessage},
        );
    }

    # check needed stuff
    if (
        !$Param{Data}->{UserLogin}
        && !$Param{Data}->{SessionID}
        )
    {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUpsert.MissingParameter',
            ErrorMessage => "CustomerUpsert: UserLogin or SessionID is required!",
        );
    }

    if ( $Param{Data}->{UserLogin} ) {

        if ( !$Param{Data}->{Password} )
        {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUpsert.MissingParameter',
                ErrorMessage => "CustomerUpsert: Password or SessionID is required!",
            );
        }
    }

    # authenticate user
    my ( $UserID, $UserType ) = $Self->Auth(
        %Param,
    );

    if ( !$UserID ) {
        return $Self->ReturnError(
            ErrorCode    => 'CustomerUpsert.AuthFail',
            ErrorMessage => "CustomerUpsert: User could not be authenticated!",
        );
    }

    my $PermissionUserID = $UserID;

    # check needed stuff
    for my $Needed (qw(Customer)) {
        if ( !$Param{Data}->{$Needed} ) {
            return $Self->ReturnError(
                ErrorCode    => 'CustomerUpsert.MissingParameter',
                ErrorMessage => "CustomerUpsert: $Needed parameter is missing or not valid!",
            );
        }
    }

    # transform single customers to an array reference
    if ( !IsArrayRefWithData( $Param{Data}{Customer} ) ) {
        $Param{Data}{Customer} = [ $Param{Data}{Customer} ];
    }

    $Result = {
        Success => 1,
        Data    => {
            Customer => [],
        }
    };

    # upsert each customer
    for my $Customer ( @{ $Param{Data}{Customer} } ) {

        # remove leading and trailing spaces
        ATTRIBUTE:
        for my $Attribute ( sort keys %{$Customer} ) {
            next ATTRIBUTE if !$Customer->{$Attribute};
            next ATTRIBUTE if ref $Customer->{$Attribute} eq 'HASH';
            next ATTRIBUTE if ref $Customer->{$Attribute} eq 'ARRAY';

            $Customer->{$Attribute} =~ s{\A\s+}{};
            $Customer->{$Attribute} =~ s{\s+\z}{};
        }

        my $CustomerCheck = $Self->_CheckCustomer( Customer => $Customer );

        # if an error occurs, return, but still include all customers already upserted
        if ( !$CustomerCheck->{Success} ) {
            $Result->{Success}       = 0;
            $Result->{ErrorMessage}  = "$CustomerCheck->{ErrorCode}: $CustomerCheck->{ErrorMessage}";
            $Result->{Data}->{Error} = {
                ErrorCode    => $CustomerCheck->{ErrorCode},
                ErrorMessage => $CustomerCheck->{ErrorMessage},
            };

            return $Result;
        }

        my $UpsertResult = $Self->_CustomerUpsert(
            Customer => $Customer,
            UserID   => $UserID,
        );

        # if an error occurs, return, but still include all customers already upserted
        if ( !$UpsertResult->{Success} ) {
            $Result->{Success}      = 0;
            $Result->{ErrorMessage} = $UpsertResult->{ErrorMessage};

            return $Result;
        }

        push @{ $Result->{Data}->{Customer} }, $UpsertResult->{Data};
    }

    return $Result;
}

=begin Internal:

=head2 _CheckCustomer()

checks if the given customer parameters are valid.

    my $CustomerCheck = $OperationObject->_CheckCustomer(
        Customer => $Customer,                               # all customer parameters
    );

    returns:

    $CustomerCheck = {
        Success => 1,                                        # if everything is OK
    }

    $CustomerCheck = {
        ErrorCode    => 'Function.Error',                    # if error
        ErrorMessage => 'Error description',
    }

=cut

sub _CheckCustomer {
    my ( $Self, %Param ) = @_;

    my $Customer = $Param{Customer};

    # check customer internally
    for my $Needed (qw(CustomerID CustomerCompanyName)) {
        if ( !$Customer->{$Needed} ) {
            return {
                ErrorCode    => 'CustomerUpsert.MissingParameter',
                ErrorMessage => "CustomerUpsert: Customer->$Needed parameter is missing!",
            };
        }
    }

    # if everything is OK then return Success
    return {
        Success => 1,
    };
}

=head2 _CustomerUpsert()

updates or inserts a customer.

    my $Response = $OperationObject->_CustomerUpsert(
        Customer => $Customer,                                        # all customer parameters
        UserID   => 123,
    );

    returns:

    $Response = {
        Success => 1,                                                 # if everething is OK
        Data    => {
            CustomerID => 123,
        }
    }

    $Response = {
        Success      => 0,                                            # if unexpected error
        ErrorMessage => "$Param{ErrorCode}: $Param{ErrorMessage}",
    }

=cut

sub _CustomerUpsert {
    my ( $Self, %Param ) = @_;

    my $Customer   = $Param{Customer};
    my $CustomerID = $Customer->{CustomerID};

    # customers are by default valid
    $Customer->{ValidID} //= 1;

    # get customer object
    my $CustomerObject = $Kernel::OM->Get('Kernel::System::CustomerCompany');

    # check whether this customer exists (update) or is new (insert)
    $Customer->{CustomerCompanyID} ||= $Customer->{CustomerID};

    my %Company = $CustomerObject->CustomerCompanyGet( CustomerID => $Customer->{CustomerCompanyID} );
    if (%Company) {

        # check if new CustomerID already exists
        if ( $Customer->{CustomerID} ne $Customer->{CustomerCompanyID} ) {
            my %Result = $CustomerObject->CustomerCompanyGet( User => $Customer->{CustomerID} );
            if (%Result) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => $Kernel::OM->Get('Kernel::Language')->Translate( 'Customer "%s" already exists.', $Customer->{CustomerID} ),
                );
                return;
            }
        }

        my $Success = $CustomerObject->CustomerCompanyUpdate(
            %{$Customer},
            UserID => $Param{UserID},
        );

        if ( !$Success ) {
            return {
                Success      => 0,
                ErrorMessage => 'Customer could not be updated, please contact the system administrator',
            };
        }
    }
    else {
        $CustomerID = $CustomerObject->CustomerCompanyAdd(
            %{$Customer},
            UserID => $Param{UserID},
        );

        if ( !$CustomerID ) {
            return {
                Success      => 0,
                ErrorMessage => 'Customer could not be inserted, please contact the system administrator',
            };
        }
    }

    my %CustomerData = $CustomerObject->CustomerCompanyGet(
        CustomerID => $CustomerID,
        UserID     => $Param{UserID},
    );

    if ( !IsHashRefWithData( \%CustomerData ) ) {
        return {
            Success      => 0,
            ErrorMessage => 'Could not get new customer information, please contact the system'
                . ' administrator',
        };
    }

    return {
        Success => 1,
        Data    => {
            CustomerID => $CustomerID,
        },
    };
}

1;

=end Internal:

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
