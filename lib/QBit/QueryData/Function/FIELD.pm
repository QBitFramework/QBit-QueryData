package QBit::QueryData::Function::FIELD;

use qbit;

use base qw(QBit::QueryData::Function);

sub init {
    my ($self) = @_;

    $self->SUPER::init();

    if ($self->args->[0] eq '') {
        $self->{'PATH'}           = $self->path;
        $self->{'__MAIN_FIELD__'} = $self->field;
    } else {
        $self->{'PATH'}           = $self->qd->_get_path($self->args->[0]);
        $self->{'__MAIN_FIELD__'} = $self->args->[0];
    }
}

sub process {
    my ($self, $row) = @_;

    return $self->qd->get_field_value_by_path($row, $row, undef, @{$self->{'PATH'}});
}

sub check {TRUE}

sub set_args {
    my ($self) = @_;

    $self->{'args'} = [$self->fields->{$self->field}];
}

sub check_args {
    my ($self) = @_;

    my $key;
    if ($self->args->[0] ne '') {
        $key = $self->args->[0];
    } else {
        $key = $self->path->[0]{'key'};
    }

    unless (exists($self->qd->{'__ALL_FIELDS__'}{$key})) {
        $self->set_error(gettext('Fields "%s" not exists', $key));

        return FALSE;
    }

    return TRUE;
}

TRUE;
