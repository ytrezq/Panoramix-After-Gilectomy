export function getPrefixedParameterName(parameterName: string, parameterPrefix?: string): string {
  if (parameterPrefix === undefined || parameterPrefix === "") {
    return parameterName;
  }

  return `${parameterPrefix}.${parameterName}`;
}
