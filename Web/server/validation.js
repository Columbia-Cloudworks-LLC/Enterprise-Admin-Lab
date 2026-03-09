// Server-side validation for lab configurations
// Mirrors PowerShell Test-EALabConfig rules exactly

const SLUG_REGEX = /^[a-z0-9][a-z0-9-]{1,48}[a-z0-9]$/;
const IP_REGEX = /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;
const CIDR_REGEX = /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/([0-9]|[1-2][0-9]|3[0-2])$/;

const VALID_DOMAINS = ['Win2012R2', 'Win2016', 'Win2019'];
const VALID_SWITCH_TYPES = ['Internal', 'Private', 'External'];
const VALID_VM_ROLES = ['DomainController', 'MemberServer', 'Client', 'Linux'];
const VALID_VM_OS = ['windowsServer2019', 'windowsServer2022', 'windowsClient', 'linux'];
const VALID_ORCHESTRATION_ENGINES = ['hybrid', 'hyperv-only'];
const VALID_ORCHESTRATION_CONTROLLERS = ['shared'];
const VALID_ORCHESTRATION_STRATEGIES = ['per-lab'];
const VALID_VM_PHASE_TAGS = ['dc-primary', 'dc-additional', 'member', 'client', 'linux'];
const VALID_VM_BOOTSTRAPS = ['winrm', 'ssh', 'none'];
const VALID_VM_EXTENDED_ROLES = ['DomainController', 'MemberServer', 'Client', 'Linux', 'DNS'];

export function validateLabConfig(config) {
  const errors = [];

  // Check metadata section exists
  if (!config.metadata) {
    errors.push({ field: 'metadata', message: 'metadata section is required' });
  } else {
    // Validate metadata.name (slug)
    if (!config.metadata.name) {
      errors.push({ field: 'metadata.name', message: 'Lab name is required' });
    } else if (!SLUG_REGEX.test(config.metadata.name)) {
      errors.push({
        field: 'metadata.name',
        message: `Lab name '${config.metadata.name}' is invalid. Must be 3-50 chars, lowercase alphanumeric or dash, starting and ending with alphanumeric.`,
      });
    }

    // Validate metadata.displayName
    if (!config.metadata.displayName || !config.metadata.displayName.trim()) {
      errors.push({ field: 'metadata.displayName', message: 'Display name is required' });
    }
  }

  // Check domain section exists
  if (!config.domain) {
    errors.push({ field: 'domain', message: 'domain section is required' });
  } else {
    // Validate domain.fqdn
    if (!config.domain.fqdn || !config.domain.fqdn.trim()) {
      errors.push({ field: 'domain.fqdn', message: 'domain.fqdn is required' });
    }

    // Validate domain.netbiosName
    if (!config.domain.netbiosName || !config.domain.netbiosName.trim()) {
      errors.push({ field: 'domain.netbiosName', message: 'domain.netbiosName is required' });
    }

    // Validate domain.functionalLevel
    if (!config.domain.functionalLevel) {
      errors.push({ field: 'domain.functionalLevel', message: 'domain.functionalLevel is required' });
    } else if (!VALID_DOMAINS.includes(config.domain.functionalLevel)) {
      errors.push({
        field: 'domain.functionalLevel',
        message: `domain.functionalLevel must be one of: ${VALID_DOMAINS.join(', ')}`,
      });
    }
  }

  // Validate networks
  if (!config.networks || !Array.isArray(config.networks) || config.networks.length === 0) {
    errors.push({ field: 'networks', message: 'At least one network definition is required' });
  } else {
    const networkNames = new Set();
    config.networks.forEach((net, idx) => {
      const prefix = `networks[${idx}]`;

      // Check name is required and unique
      if (!net.name || !net.name.trim()) {
        errors.push({ field: `${prefix}.name`, message: 'Network name is required' });
      } else {
        const lowerName = net.name.toLowerCase();
        if (networkNames.has(lowerName)) {
          errors.push({ field: `${prefix}.name`, message: `Duplicate network name '${net.name}'` });
        }
        networkNames.add(lowerName);
      }

      // Check switchType
      if (!net.switchType) {
        errors.push({ field: `${prefix}.switchType`, message: 'switchType is required' });
      } else if (!VALID_SWITCH_TYPES.includes(net.switchType)) {
        errors.push({
          field: `${prefix}.switchType`,
          message: `switchType must be one of: ${VALID_SWITCH_TYPES.join(', ')}`,
        });
      }

      // Check subnet (CIDR)
      if (!net.subnet || !net.subnet.trim()) {
        errors.push({ field: `${prefix}.subnet`, message: 'Subnet (CIDR) is required' });
      } else if (!CIDR_REGEX.test(net.subnet)) {
        errors.push({ field: `${prefix}.subnet`, message: `'${net.subnet}' is not valid CIDR notation` });
      }

      // Check gateway if provided
      if (net.gateway && !IP_REGEX.test(net.gateway)) {
        errors.push({ field: `${prefix}.gateway`, message: `'${net.gateway}' is not a valid IP address` });
      }

      // Check dnsServers if provided
      if (net.dnsServers && Array.isArray(net.dnsServers)) {
        net.dnsServers.forEach((dns, dnsIdx) => {
          if (dns && !IP_REGEX.test(dns)) {
            errors.push({ field: `${prefix}.dnsServers[${dnsIdx}]`, message: `'${dns}' is not a valid IP address` });
          }
        });
      }
    });
  }

  // Validate vmDefinitions
  if (!config.vmDefinitions || !Array.isArray(config.vmDefinitions) || config.vmDefinitions.length === 0) {
    errors.push({ field: 'vmDefinitions', message: 'At least one VM definition is required' });
  } else {
    const vmNames = new Set();
    let hasDomainController = false;

    config.vmDefinitions.forEach((vm, idx) => {
      const prefix = `vmDefinitions[${idx}]`;

      // Check VM name is required and unique
      if (!vm.name || !vm.name.trim()) {
        errors.push({ field: `${prefix}.name`, message: 'VM name is required' });
      } else {
        const lowerName = vm.name.toLowerCase();
        if (vmNames.has(lowerName)) {
          errors.push({ field: `${prefix}.name`, message: `Duplicate VM name '${vm.name}'` });
        }
        vmNames.add(lowerName);
      }

      // Check role
      if (!vm.role) {
        errors.push({ field: `${prefix}.role`, message: 'VM role is required' });
      } else if (!VALID_VM_ROLES.includes(vm.role)) {
        errors.push({
          field: `${prefix}.role`,
          message: `VM role must be one of: ${VALID_VM_ROLES.join(', ')}`,
        });
      } else if (vm.role === 'DomainController') {
        hasDomainController = true;
      }

      // Check OS
      if (!vm.os) {
        errors.push({ field: `${prefix}.os`, message: 'VM OS is required' });
      } else if (!VALID_VM_OS.includes(vm.os)) {
        errors.push({
          field: `${prefix}.os`,
          message: `VM OS must be one of: ${VALID_VM_OS.join(', ')}`,
        });
      }

      // Check generation
      if (vm.generation === undefined || vm.generation === null) {
        errors.push({ field: `${prefix}.generation`, message: 'VM generation is required' });
      } else if (![1, 2].includes(vm.generation)) {
        errors.push({ field: `${prefix}.generation`, message: 'VM generation must be 1 or 2' });
      }

      // Check secureBoot (only on Gen 2)
      if (vm.secureBoot && vm.generation !== 2) {
        errors.push({ field: `${prefix}.secureBoot`, message: 'secureBoot can only be enabled on Generation 2 VMs' });
      }

      // Check tpmEnabled (only on Gen 2 + windowsClient)
      if (vm.tpmEnabled && (vm.generation !== 2 || vm.os !== 'windowsClient')) {
        errors.push({
          field: `${prefix}.tpmEnabled`,
          message: 'tpmEnabled is only supported on Generation 2 windowsClient VMs',
        });
      }

      // Check hardware
      if (vm.hardware) {
        const { cpuCount, memoryMB, diskSizeGB } = vm.hardware;

        if (cpuCount !== undefined && (cpuCount < 1 || cpuCount > 16)) {
          errors.push({ field: `${prefix}.hardware.cpuCount`, message: 'cpuCount is out of range (1-16)' });
        }

        if (memoryMB !== undefined && (memoryMB < 512 || memoryMB > 65536)) {
          errors.push({ field: `${prefix}.hardware.memoryMB`, message: 'memoryMB is out of range (512-65536)' });
        }

        if (diskSizeGB !== undefined && (diskSizeGB < 20 || diskSizeGB > 2000)) {
          errors.push({ field: `${prefix}.hardware.diskSizeGB`, message: 'diskSizeGB is out of range (20-2000)' });
        }
      }

      // Check network reference
      if (!vm.network || !vm.network.trim()) {
        errors.push({ field: `${prefix}.network`, message: 'Network reference is required' });
      } else if (config.networks) {
        const networkExists = config.networks.some((net) => net.name === vm.network);
        if (!networkExists) {
          errors.push({
            field: `${prefix}.network`,
            message: `Network '${vm.network}' is not defined in the networks array`,
          });
        }
      }

      // Check staticIP if provided
      if (vm.staticIP && !IP_REGEX.test(vm.staticIP)) {
        errors.push({ field: `${prefix}.staticIP`, message: `'${vm.staticIP}' is not a valid IP address` });
      }

      if (vm.orchestration) {
        if (vm.orchestration.phaseTag && !VALID_VM_PHASE_TAGS.includes(vm.orchestration.phaseTag)) {
          errors.push({
            field: `${prefix}.orchestration.phaseTag`,
            message: `phaseTag must be one of: ${VALID_VM_PHASE_TAGS.join(', ')}`,
          });
        }

        if (vm.orchestration.bootstrap && !VALID_VM_BOOTSTRAPS.includes(vm.orchestration.bootstrap)) {
          errors.push({
            field: `${prefix}.orchestration.bootstrap`,
            message: `bootstrap must be one of: ${VALID_VM_BOOTSTRAPS.join(', ')}`,
          });
        }
      }

      const vmRoles = Array.isArray(vm.roles) && vm.roles.length > 0 ? vm.roles : [vm.role];
      const isDomainController = vmRoles.includes('DomainController');
      vmRoles.forEach((roleItem) => {
        if (roleItem && !VALID_VM_EXTENDED_ROLES.includes(roleItem)) {
          errors.push({
            field: `${prefix}.roles`,
            message: `role '${roleItem}' is not supported. Allowed values: ${VALID_VM_EXTENDED_ROLES.join(', ')}`,
          });
        }
      });

      if (isDomainController) {
        const deploymentType = vm.domainController?.deploymentType;
        if (deploymentType && !['newForest', 'additional'].includes(deploymentType)) {
          errors.push({
            field: `${prefix}.domainController.deploymentType`,
            message: "deploymentType must be 'newForest' or 'additional'",
          });
        }

        if (deploymentType === 'additional' && !vm.domainController?.sourceDcName) {
          errors.push({
            field: `${prefix}.domainController.sourceDcName`,
            message: 'sourceDcName is required when deploymentType is additional',
          });
        }
      }

      if (vm.guestConfiguration) {
        const guest = vm.guestConfiguration;
        if (guest.computerName && guest.computerName.length > 15) {
          errors.push({
            field: `${prefix}.guestConfiguration.computerName`,
            message: 'computerName must be 15 characters or less',
          });
        }

        if (guest.network) {
          const networkPrefix = `${prefix}.guestConfiguration.network`;
          if (guest.network.ipAddress && !IP_REGEX.test(guest.network.ipAddress)) {
            errors.push({ field: `${networkPrefix}.ipAddress`, message: `'${guest.network.ipAddress}' is not a valid IP address` });
          }
          if (guest.network.subnetMask && !IP_REGEX.test(guest.network.subnetMask)) {
            errors.push({ field: `${networkPrefix}.subnetMask`, message: `'${guest.network.subnetMask}' is not a valid subnet mask` });
          }
          if (guest.network.gateway && !IP_REGEX.test(guest.network.gateway)) {
            errors.push({ field: `${networkPrefix}.gateway`, message: `'${guest.network.gateway}' is not a valid gateway IP` });
          }
          if (Array.isArray(guest.network.dnsServers)) {
            guest.network.dnsServers.forEach((dnsValue, dnsIdx) => {
              if (dnsValue && !IP_REGEX.test(dnsValue)) {
                errors.push({ field: `${networkPrefix}.dnsServers[${dnsIdx}]`, message: `'${dnsValue}' is not a valid IP address` });
              }
            });
          }
          if (vm.staticIP && guest.network.ipAddress && vm.staticIP !== guest.network.ipAddress) {
            errors.push({
              field: `${networkPrefix}.ipAddress`,
              message: 'guestConfiguration.network.ipAddress must match staticIP when both are specified',
            });
          }
        }

        const hasInlineDomainAdmin = !!(config.credentials?.domainAdminUser && config.credentials?.domainAdminPassword);
        if (guest.domainJoin?.enabled === true && !guest.domainJoin?.credentialRef && !hasInlineDomainAdmin) {
          errors.push({
            field: `${prefix}.guestConfiguration.domainJoin.credentialRef`,
            message: 'credentialRef is required when domainJoin.enabled is true unless credentials.domainAdminUser/domainAdminPassword are set',
          });
        }
        if (guest.domainJoin?.enabled === true && isDomainController) {
          errors.push({
            field: `${prefix}.guestConfiguration.domainJoin.enabled`,
            message: 'DomainController VMs should not set domainJoin.enabled to true',
          });
        }
      }
    });

    // At least one DomainController required
    if (!hasDomainController) {
      errors.push({
        field: 'vmDefinitions',
        message: 'At least one VM with role DomainController is required',
      });
    }
  }

  const hasNewForestDc = config.vmDefinitions?.some((vm) => {
    const vmRoles = Array.isArray(vm.roles) && vm.roles.length > 0 ? vm.roles : [vm.role];
    if (!vmRoles.includes('DomainController')) {
      return false;
    }
    const deploymentType = vm.domainController?.deploymentType;
    return !deploymentType || deploymentType === 'newForest';
  });
  if (!hasNewForestDc) {
    errors.push({
      field: 'vmDefinitions',
      message: 'At least one DomainController VM must deploy as newForest',
    });
  }

  // Validate globalHardwareDefaults if present
  if (config.globalHardwareDefaults) {
    const { cpuCount, memoryMB, diskSizeGB } = config.globalHardwareDefaults;

    if (cpuCount !== undefined && (cpuCount < 1 || cpuCount > 16)) {
      errors.push({ field: 'globalHardwareDefaults.cpuCount', message: 'cpuCount is out of range (1-16)' });
    }

    if (memoryMB !== undefined && (memoryMB < 512 || memoryMB > 65536)) {
      errors.push({ field: 'globalHardwareDefaults.memoryMB', message: 'memoryMB is out of range (512-65536)' });
    }

    if (diskSizeGB !== undefined && (diskSizeGB < 20 || diskSizeGB > 2000)) {
      errors.push({ field: 'globalHardwareDefaults.diskSizeGB', message: 'diskSizeGB is out of range (20-2000)' });
    }
  }

  // Validate orchestration section if present
  if (config.orchestration) {
    if (config.orchestration.engine && !VALID_ORCHESTRATION_ENGINES.includes(config.orchestration.engine)) {
      errors.push({
        field: 'orchestration.engine',
        message: `orchestration.engine must be one of: ${VALID_ORCHESTRATION_ENGINES.join(', ')}`,
      });
    }

    if (config.orchestration.controller && !VALID_ORCHESTRATION_CONTROLLERS.includes(config.orchestration.controller)) {
      errors.push({
        field: 'orchestration.controller',
        message: `orchestration.controller must be one of: ${VALID_ORCHESTRATION_CONTROLLERS.join(', ')}`,
      });
    }

    if (config.orchestration.inventoryStrategy && !VALID_ORCHESTRATION_STRATEGIES.includes(config.orchestration.inventoryStrategy)) {
      errors.push({
        field: 'orchestration.inventoryStrategy',
        message: `orchestration.inventoryStrategy must be one of: ${VALID_ORCHESTRATION_STRATEGIES.join(', ')}`,
      });
    }
  }

  if (config.credentials) {
    ['localAdminRef', 'domainAdminRef', 'dsrmRef'].forEach((fieldName) => {
      const value = config.credentials[fieldName];
      if (value && String(value).trim().length < 3) {
        errors.push({
          field: `credentials.${fieldName}`,
          message: `${fieldName} must be at least 3 characters when provided`,
        });
      }
    });

    const inlinePairs = [
      ['localAdminUser', 'localAdminPassword'],
      ['domainAdminUser', 'domainAdminPassword'],
    ];
    inlinePairs.forEach(([userField, passwordField]) => {
      const hasUser = !!String(config.credentials[userField] || '').trim();
      const hasPassword = !!String(config.credentials[passwordField] || '').trim();
      if (hasUser !== hasPassword) {
        errors.push({
          field: `credentials.${userField}`,
          message: `${userField} and ${passwordField} must be provided together when using inline credentials`,
        });
      }
    });
  }

  if (config.guestDefaults) {
    const installTimeoutMinutes = Number(config.guestDefaults.installTimeoutMinutes);
    if (!Number.isNaN(installTimeoutMinutes) && (installTimeoutMinutes < 5 || installTimeoutMinutes > 480)) {
      errors.push({
        field: 'guestDefaults.installTimeoutMinutes',
        message: 'installTimeoutMinutes must be between 5 and 480',
      });
    }

    const postInstallTimeoutMinutes = Number(config.guestDefaults.postInstallTimeoutMinutes);
    if (!Number.isNaN(postInstallTimeoutMinutes) && (postInstallTimeoutMinutes < 5 || postInstallTimeoutMinutes > 480)) {
      errors.push({
        field: 'guestDefaults.postInstallTimeoutMinutes',
        message: 'postInstallTimeoutMinutes must be between 5 and 480',
      });
    }
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}
