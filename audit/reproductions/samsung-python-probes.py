"""Preserved offline probe body executed during the Samsung source audit.

Requires the already-inspected source snapshots at the original temporary paths.
Does not install dependencies or contact a TV. Expected output is preserved in
samsung-python-probes.stdout.txt. The audited helper's sleeps use zero delay.
"""

import sys, socket, urllib.request, logging
from unittest.mock import patch, MagicMock
sys.path.insert(0, '/private/tmp/samsungctl-0.7.0')
sys.path.insert(0, '/private/tmp/tv-remote-audit-samsung')
logging.disable(logging.CRITICAL)
with patch('socket.socket', side_effect=AssertionError('Network forbidden')), patch('urllib.request.urlopen', side_effect=AssertionError('Network forbidden')):
    import samsungctl
    from helpers import tvcon, tvinfo
    import samsung_remote
    print('Pinned Samsungctl version:', samsungctl.__version__)
    print('Pinned dependency exposes Config:', hasattr(samsungctl, 'Config'))
    assert not hasattr(samsungctl, 'Config')
    assert tvcon.send({'host':'192.0.2.10','method':'websocket'}, 'KEY_VOLUP', 0) is False
    print('Pinned dependency command result: False before any network access')
    with patch.object(samsungctl, 'Config', create=True) as config, patch.object(samsungctl, 'Remote') as remote:
        remote.return_value.__enter__.return_value.control.return_value = False
        result = tvcon.send({'host':'192.0.2.10','method':'websocket'}, 'KEY_VOLUP', 0)
        assert result is True
        assert config.call_args.kwargs['port'] == 55000
        print('Default transport port:', config.call_args.kwargs['port'])
        print('Remote.control False is reported by wrapper as:', result)
    with patch.object(sys, 'argv', ['samsung_remote.py']):
        try:
            samsung_remote.main()
        except AttributeError as error:
            print('No-arguments entrypoint:', str(error))
        else:
            raise AssertionError('Expected no-arguments crash')
    with patch.object(sys, 'argv', ['samsung_remote.py','-i','192.0.2.10','-k','KEY_VOLUP']), patch.object(samsung_remote,'setup_logging'), patch.object(tvcon,'send',return_value=False):
        samsung_remote.main()
        print('Failed key command returns normally (process exit 0)')
    print('All five offline probes confirmed; socket creation and URL network access forbidden.')
