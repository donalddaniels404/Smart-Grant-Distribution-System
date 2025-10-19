import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";
import { initSimnet } from "@hirosystems/clarinet-sdk";

const simnet = await initSimnet();

describe("Smart Grant Distribution System", () => {
  it("should initialize contract successfully", () => {
    const deployer = simnet.getAccounts().get("deployer")!;
    
    const { result } = simnet.callPublicFn(
      "Smart-Grant-Distribution-System",
      "initialize-contract",
      [],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
  });
  
  it("should create grant successfully", () => {
    const deployer = simnet.getAccounts().get("deployer")!;
    const recipient = simnet.getAccounts().get("wallet_1")!;
    
    const { result } = simnet.callPublicFn(
      "Smart-Grant-Distribution-System",
      "create-grant",
      [
        Cl.principal(recipient),
        Cl.uint(1000000),
        Cl.uint(3)
      ],
      deployer
    );
    
    expect(result).toBeOk(Cl.uint(1));
  });
  
  it("should add validator successfully", () => {
    const deployer = simnet.getAccounts().get("deployer")!;
    const validator = simnet.getAccounts().get("wallet_2")!;
    
    const { result } = simnet.callPublicFn(
      "Smart-Grant-Distribution-System",
      "add-validator",
      [Cl.principal(validator)],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
  });
  
  it("should register arbitrator successfully", () => {
    const deployer = simnet.getAccounts().get("deployer")!;
    
    const { result } = simnet.callPublicFn(
      "Smart-Grant-Distribution-System",
      "register-arbitrator",
      [Cl.stringAscii("Technical Disputes")],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
  });
  
  it("should initialize analytics system", () => {
    const deployer = simnet.getAccounts().get("deployer")!;
    
    const { result } = simnet.callPublicFn(
      "Smart-Grant-Distribution-System",
      "initialize-analytics-system",
      [],
      deployer
    );
    
    expect(result).toBeOk(Cl.bool(true));
  });
});
