// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from 'forge-std/Test.sol';
import {Logger} from 'src/deployments/utils/Logger.sol';

contract LoggerTest is Test {
  string internal constant OUTPUT_DIR = 'output/reports/deployments/test/';

  function test_writeAddress() public {
    Logger logger = new Logger(OUTPUT_DIR);
    address value = makeAddr('test');

    logger.write('myAddr', value);

    string memory json = logger.getJson();
    assertEq(vm.parseJsonAddress(json, '$.myAddr'), value);
  }

  function test_writeUint() public {
    Logger logger = new Logger(OUTPUT_DIR);

    logger.write('myUint', 42);

    string memory json = logger.getJson();
    assertEq(vm.parseJsonUint(json, '$.myUint'), 42);
  }

  function test_writeString() public {
    Logger logger = new Logger(OUTPUT_DIR);

    logger.write('hello world');

    string memory json = logger.getJson();
    assertEq(vm.parseJsonString(json, '$.message'), 'hello world');
  }

  function test_writeGroupAddress() public {
    Logger logger = new Logger(OUTPUT_DIR);

    address addrA = makeAddr('a');
    address addrB = makeAddr('b');

    Logger.AddressEntry[] memory entries = new Logger.AddressEntry[](2);
    entries[0] = Logger.AddressEntry({label: 'alpha', value: addrA});
    entries[1] = Logger.AddressEntry({label: 'beta', value: addrB});

    logger.writeGroup('myGroup', entries);

    string memory json = logger.getJson();
    assertEq(vm.parseJsonAddress(json, '$.myGroup.alpha'), addrA);
    assertEq(vm.parseJsonAddress(json, '$.myGroup.beta'), addrB);
  }

  function test_writeGroupValue() public {
    Logger logger = new Logger(OUTPUT_DIR);

    Logger.ValueEntry[] memory entries = new Logger.ValueEntry[](2);
    entries[0] = Logger.ValueEntry({label: 'x', value: 100});
    entries[1] = Logger.ValueEntry({label: 'y', value: 200});

    logger.writeGroup('nums', entries);

    string memory json = logger.getJson();
    assertEq(vm.parseJsonString(json, '$.nums.x'), '100');
    assertEq(vm.parseJsonString(json, '$.nums.y'), '200');
  }

  function test_multipleWrites() public {
    Logger logger = new Logger(OUTPUT_DIR);

    address addr = makeAddr('multi');
    logger.write('addr', addr);
    logger.write('count', 7);
    logger.write('status message');

    string memory json = logger.getJson();
    assertEq(vm.parseJsonAddress(json, '$.addr'), addr);
    assertEq(vm.parseJsonUint(json, '$.count'), 7);
    assertEq(vm.parseJsonString(json, '$.message'), 'status message');
  }

  function test_save() public {
    Logger logger = new Logger(OUTPUT_DIR);

    address addr = makeAddr('save-test');
    logger.write('saved', addr);
    logger.write('num', 123);

    vm.createDir(OUTPUT_DIR, true);
    logger.save({fileName: 'logger-unit-test', withTimestamp: false});

    string memory filePath = string.concat(
      OUTPUT_DIR,
      vm.toString(block.chainid),
      '-logger-unit-test.json'
    );
    string memory json = vm.readFile(filePath);
    assertEq(vm.parseJsonAddress(json, '$.saved'), addr);
    assertEq(vm.parseJsonUint(json, '$.num'), 123);

    vm.removeFile(filePath);
  }

  function test_getJson_returnsAccumulatedState() public {
    Logger logger = new Logger(OUTPUT_DIR);
    address addr = makeAddr('getjson');

    // Before any writes, getJson returns the raw key
    string memory jsonBefore = logger.getJson();
    assertEq(jsonBefore, 'root');

    // After a write, getJson returns valid JSON with the key
    logger.write('check', addr);
    string memory jsonAfter = logger.getJson();
    assertEq(vm.parseJsonAddress(jsonAfter, '$.check'), addr);
  }
}
