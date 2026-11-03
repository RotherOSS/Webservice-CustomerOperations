# --
# OTOBO is a web-based ticketing system for service organisations.
# --
# Copyright (C) 2018 Perl-Services.de, http://perl-services.de
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

package Kernel::GenericInterface::Operation::Customer::Common;

use strict;
use warnings;

# core modules
use MIME::Base64();
use Mail::Address;

# CPAN modules

# OTOBO modules
use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

=head1 NAME

Kernel::GenericInterface::Operation::Customer::Common - Base class for all Customer Operations

=head1 PUBLIC INTERFACE

=head2 Init()

initialize the operation by checking the web service configuration and gather of the dynamic fields

    my $Return = $CommonObject->Init(
        WebserviceID => 1,
    );

returns:

    $Return = {
        Success => 1,                       # or 0 in case of failure,
        ErrorMessage => 'Error Message',
    }

=cut

sub Init {
    my ( $Self, %Param ) = @_;

    # check needed
    if ( !$Param{WebserviceID} ) {
        return {
            Success      => 0,
            ErrorMessage => "Got no WebserviceID!",
        };
    }

    # get web service configuration
    my $Webservice = $Kernel::OM->Get('Kernel::System::GenericInterface::Webservice')->WebserviceGet(
        ID => $Param{WebserviceID},
    );

    if ( !IsHashRefWithData($Webservice) ) {
        return {
            Success      => 0,
            ErrorMessage =>
                'Could not determine Web service configuration'
                . ' in Kernel::GenericInterface::Operation::Customer::Common::new()',
        };
    }

    # get the dynamic fields
    my $DynamicFieldList = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid      => 1,
        ObjectType => [ 'CustomerUser', 'CustomerCompany', ],
    );

    # create a Dynamic Fields lookup table (by name)
    DYNAMICFIELD:
    for my $DynamicField ( $DynamicFieldList->@* ) {
        next DYNAMICFIELD unless $DynamicField;
        next DYNAMICFIELD unless IsHashRefWithData($DynamicField);
        next DYNAMICFIELD unless $DynamicField->{Name};

        $Self->{DynamicFieldLookup}->{ $DynamicField->{Name} } = $DynamicField;
    }

    return {
        Success => 1,
    };
}

1;

=head1 TERMS AND CONDITIONS

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
