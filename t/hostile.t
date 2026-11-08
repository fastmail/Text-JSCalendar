#!perl
# Hostile input: refused or bounded, never a crash or a hang.
use strict;
use warnings;
use Test::More;
use Text::JSCalendar;

my $jscal = Text::JSCalendar->new;

# Text::VCardFast recurses in C once per BEGIN: deep nesting would overflow
# the stack and kill the process.  It is refused first.
{
  my $n = 60000;
  my $v = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTART:20260101T100000Z\r\n"
        . ("BEGIN:VALARM\r\n" x $n) . ("END:VALARM\r\n" x $n) . "END:VEVENT\r\nEND:VCALENDAR\r\n";
  my @e = eval { $jscal->vcalendarToEvents($v) };
  like($@, qr/nested more than/, 'components nested 60000 deep: refused, not a crash');
  ok(eval { $jscal->vcalendarToEvents("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:u\r\nDTSTART:20260101T100000Z\r\n"
     . "BEGIN:VALARM\r\nACTION:DISPLAY\r\nTRIGGER:-PT5M\r\nEND:VALARM\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"); 1 },
     'ordinary nesting still parses') or diag $@;
}

# Rules that could expand for ever, or close to it, end within a bound
{
  use Time::HiRes qw(time);
  my $ev = sub { +{ '@type' => 'Event', uid => 'r', start => '2026-01-01T00:00:00', timeZone => 'Etc/UTC',
                    duration => 'PT1M', recurrenceRule => { '@type' => 'RecurrenceRule', %{ $_[0] } } } };
  my @cases = (
    [ { frequency => 'minutely', bySetPosition => [2] }, {}, 'MINUTELY;BYSETPOS=2, unbounded' ],
    [ { frequency => 'secondly', count => 1e12 }, { after => '2026-01-01T00:00:00' }, 'SECONDLY with a huge count' ],
    [ { frequency => 'secondly', bySecond => [60] }, { after => '2026-01-01T00:00:00', before => '2026-02-01T00:00:00' }, 'SECONDLY;BYSECOND=60 over a month' ],
  );
  for my $c (@cases) {
    my ($rule, $win, $desc) = @$c;
    my $t0 = time;
    my @o = eval { local $SIG{ALRM} = sub { die "timeout\n" }; alarm 30; my @r = Text::JSCalendar->occurrences($ev->($rule), %$win); alarm 0; @r };
    alarm 0;
    my $took = time - $t0;
    ok($@ ne "timeout\n" && $took < 10, "$desc: bounded") or diag "took ${took}s $@";
  }
  for my $bad ([ { frequency => 'yearly', byYearDay => [ (367) x 2 ] }, 'byYearDay 367' ],
               [ { frequency => 'yearly', byYearDay => [ (1) x 2000 ] }, 'a byYearDay list of 2000' ],
               [ { frequency => 'monthly', byMonthDay => [32] }, 'byMonthDay 32' ]) {
    my ($rule, $desc) = @$bad;
    ok(!eval { Text::JSCalendar->occurrences($ev->($rule), max => 3); 1 }, "$desc: refused");
  }
}

done_testing;
