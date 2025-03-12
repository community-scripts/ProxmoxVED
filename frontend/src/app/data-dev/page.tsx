"use client";

import React, { useState, useEffect } from "react";
import FilterComponent from "../../components/FilterComponent";

interface DataModel {
  status: string;
  type: string;
  nsapp: string;
  os_type: string;
  disk_size: number;
  core_count: number;
  ram_size: number;
  method: string;
  pve_version: string;
  created_at: string;
}

const DataFetcher: React.FC = () => {
  const [data, setData] = useState<DataModel[]>([]);
  const [filteredData, setFilteredData] = useState<DataModel[]>([]);
  const [filters, setFilters] = useState<Record<string, any>>({});

  useEffect(() => {
    const fetchData = async () => {
      const response = await fetch("https://api.htl-braunau.at/data/json");
      const result: DataModel[] = await response.json();
      setData(result);
      setFilteredData(result);
    };

    fetchData();
  }, []);

  const applyFilters = async (column: string, operator: string, value: any) => {
    setFilters((prev) => {
      const updatedFilters = { ...prev };
      if (!updatedFilters[column]) updatedFilters[column] = [];

      // Prevent duplicate filters
      const alreadyExists = updatedFilters[column].some((filter: { operator: string; value: any }) =>
        filter.operator === operator && filter.value === value
      );

      if (!alreadyExists) {
        updatedFilters[column].push({ operator, value });
      }

      return updatedFilters;
    });
  };

  const removeFilter = (column: string, index: number) => {
    setFilters((prev) => {
      const updatedFilters = { ...prev };
      updatedFilters[column] = updatedFilters[column].filter((_: any, i: number) => i !== index);

      // If no filters remain, remove the column entry
      if (updatedFilters[column].length === 0) delete updatedFilters[column];

      return updatedFilters;
    });
  };


  useEffect(() => {
    let filtered = [...data];

    Object.keys(filters).forEach((key) => {
      if (!filters[key] || filters[key].length === 0) return;

      filtered = filtered.filter((item) => {
        const itemValue = item[key as keyof DataModel];

        return filters[key].some(({ operator, value }: { operator: string; value: any }) => {
          if (typeof itemValue === "number") {
            value = parseFloat(value);
            if (operator === "greater") return itemValue > value;
            if (operator === "greater or equal") return itemValue >= value;
            if (operator === "less") return itemValue < value;
            if (operator === "less or equal") return itemValue <= value;
          }

          if (typeof itemValue === "string") {
            if (operator === "equals") return itemValue.toLowerCase() === value.toLowerCase();
            if (operator === "not equals") return itemValue.toLowerCase() !== value.toLowerCase();
            if (operator === "contains") return itemValue.toLowerCase().includes(value.toLowerCase());
            if (operator === "does not contain") return !itemValue.toLowerCase().includes(value.toLowerCase());
          }

          return false;
        });
      });
    });

    setFilteredData(filtered);
  }, [filters, data]);

  const columns: { key: string; type: "text" | "number" }[] = [
    { key: "status", type: "text" },
    { key: "type", type: "text" },
    { key: "nsapp", type: "text" },
    { key: "os_type", type: "text" },
    { key: "disk_size", type: "number" },
    { key: "core_count", type: "number" },
    { key: "ram_size", type: "number" },
    { key: "method", type: "text" },
    { key: "pve_version", type: "text" },
    { key: "created_at", type: "text" }
  ];

  return (
    <div className="p-6 mt-20">
      <h1 className="text-2xl font-bold mb-4 text-center">Created LXCs</h1>

      <table className="min-w-full table-auto border-collapse">
        <thead>
          <tr>
            {columns.map(({ key, type }) => (
              <th key={key} className="px-4 py-2 border-b text-left">
                <div className="flex items-center space-x-2">
                  <span className="font-semibold">{key}</span>
                  <FilterComponent
                    column={key}
                    type={type}
                    activeFilters={filters[key] || []}
                    onApplyFilter={applyFilters}
                    onRemoveFilter={removeFilter}
                    allData={data}
                  />
                </div>
              </th>
            ))}
          </tr>
        </thead>

        {/* Filters Row - Displays below headers */}
        <thead>
          <tr>
            {columns.map(({ key }) => (
              <th key={key} className="px-4 py-2 border-b text-left">
                {filters[key] && filters[key].length > 0 ? (
                  <div className="flex flex-wrap gap-1">
                    {filters[key].map((filter: { operator: string; value: any }, index: number) => (
                      <div key={`${key}-${filter.value}-${index}`} className="bg-gray-800 text-white px-2 py-1 rounded flex items-center">
					<span className="text-sm italic">
					  {filter.operator} <b>&quot;{filter.value}&quot;</b>
					</span>
                        <button className="text-red-500 ml-2" onClick={() => removeFilter(key, index)}>
                          ✖
                        </button>
                      </div>
                    ))}
                  </div>
                ) : (
                  <span className="text-gray-500">—</span>
                )}
              </th>
            ))}
          </tr>
        </thead>


        <tbody>
          {filteredData.length > 0 ? (
            filteredData.map((item, index) => (
              <tr key={index}>
                <td className="px-4 py-2 border-b">{item.status}</td>
                <td className="px-4 py-2 border-b">{item.type}</td>
                <td className="px-4 py-2 border-b">{item.nsapp}</td>
                <td className="px-4 py-2 border-b">{item.os_type}</td>
                <td className="px-4 py-2 border-b">{item.disk_size}</td>
                <td className="px-4 py-2 border-b">{item.core_count}</td>
                <td className="px-4 py-2 border-b">{item.ram_size}</td>
                <td className="px-4 py-2 border-b">{item.method}</td>
                <td className="px-4 py-2 border-b">{item.pve_version}</td>
                <td className="px-4 py-2 border-b">{item.created_at}</td>
              </tr>
            ))
          ) : (
            <tr>
              <td colSpan={columns.length} className="px-4 py-2 text-center text-gray-500">
                No results found
              </td>
            </tr>
          )}
        </tbody>
      </table>
    </div>
  );
};

export default DataFetcher;
